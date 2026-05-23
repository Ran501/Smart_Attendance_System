const pool = require('../database/pool');

const THRESHOLD_PCT = 90;
const MIN_HELD_UNITS_BEFORE_ALERT = 1;

function computePlanFromHours(semesterTotalHours, hoursPerWeek) {
  const hours = Math.max(1, parseInt(semesterTotalHours, 10) || 0);
  const perWeek = Math.max(0.5, parseFloat(hoursPerWeek) || 1);
  const plannedSessionCount = hours;
  const maxAllowedAbsences = Math.max(0, Math.floor(plannedSessionCount * (1 - THRESHOLD_PCT / 100)));
  const estimatedWeeks = Math.max(1, Math.ceil(hours / perWeek));
  return {
    semesterTotalHours: hours,
    hoursPerWeek: perWeek,
    plannedSessionCount,
    maxAllowedAbsences,
    estimatedWeeks,
  };
}

async function getSubjectPlan(subjectId) {
  const result = await pool.query(
    `SELECT id, name, semester_total_hours, hours_per_week, planned_session_count,
            max_allowed_absences, extra_classes_recorded, cancelled_classes_recorded
     FROM subjects WHERE id = $1`,
    [subjectId],
  );
  return result.rows[0] || null;
}

async function upsertSubjectPlan(subjectId, { semesterTotalHours, hoursPerWeek }) {
  const plan = computePlanFromHours(semesterTotalHours, hoursPerWeek);
  await pool.query(
    `UPDATE subjects SET
       semester_total_hours = $2,
       hours_per_week = $3,
       planned_session_count = $4,
       max_allowed_absences = $5
     WHERE id = $1`,
    [
      subjectId,
      plan.semesterTotalHours,
      plan.hoursPerWeek,
      plan.plannedSessionCount,
      plan.maxAllowedAbsences,
    ],
  );
  return plan;
}

async function recordPlanAdjustment(subjectId, { extraClasses = 0, cancelledClasses = 0 }) {
  if (extraClasses > 0) {
    await pool.query(
      `UPDATE subjects SET extra_classes_recorded = COALESCE(extra_classes_recorded, 0) + $2 WHERE id = $1`,
      [subjectId, extraClasses],
    );
  }
  if (cancelledClasses > 0) {
    await pool.query(
      `UPDATE subjects SET cancelled_classes_recorded = COALESCE(cancelled_classes_recorded, 0) + $2 WHERE id = $1`,
      [subjectId, cancelledClasses],
    );
  }
  return getSubjectPlan(subjectId);
}

async function getStudentSubjectStats(studentId, subjectId) {
  const heldResult = await pool.query(
    `SELECT COALESCE(SUM(COALESCE(s.session_units, 1)), 0)::int AS held_units
     FROM attendance_sessions s
     WHERE s.subject_id = $2 AND s.status IN ('closed', 'expired')`,
    [studentId, subjectId],
  );
  const heldUnits = heldResult.rows[0]?.held_units ?? 0;

  const statusResult = await pool.query(
    `SELECT
       COALESCE(SUM(COALESCE(s.session_units, 1)) FILTER (WHERE ar.status IN ('PRESENT', 'LATE')), 0)::int AS present_units,
       COALESCE(SUM(COALESCE(s.session_units, 1)) FILTER (WHERE COALESCE(ar.status, 'ABSENT') = 'ABSENT'), 0)::int AS absent_units,
       COALESCE(SUM(COALESCE(s.session_units, 1)) FILTER (WHERE ar.status = 'MEDICAL_LEAVE'), 0)::int AS medical_units,
       COALESCE(SUM(COALESCE(s.session_units, 1)) FILTER (WHERE ar.status = 'OFFICIAL_LEAVE'), 0)::int AS official_units
     FROM attendance_sessions s
     LEFT JOIN attendance_records ar ON ar.session_id = s.id AND ar.student_id = $1
     WHERE s.subject_id = $2 AND s.status IN ('closed', 'expired')`,
    [studentId, subjectId],
  );

  const row = statusResult.rows[0] || {};
  const presentUnits = row.present_units ?? 0;
  const absentUnits = row.absent_units ?? 0;

  const currentPct = heldUnits > 0 ? (presentUnits / heldUnits) * 100 : 100;
  const afterOneMoreAbsentPct =
    heldUnits > 0 ? (presentUnits / (heldUnits + 1)) * 100 : 100;

  return {
    heldUnits,
    presentUnits,
    absentUnits,
    medicalUnits: row.medical_units ?? 0,
    officialUnits: row.official_units ?? 0,
    currentPct,
    afterOneMoreAbsentPct,
  };
}

function formatNextSessionHint(lastSessionAt) {
  if (!lastSessionAt) return 'Check your timetable';
  const last = new Date(lastSessionAt);
  if (Number.isNaN(last.getTime())) return 'Check your timetable';
  const next = new Date(last);
  next.setDate(next.getDate() + 7);
  return next.toLocaleDateString('en-GB', {
    weekday: 'short',
    day: 'numeric',
    month: 'short',
  });
}

async function getLastSessionAt(subjectId) {
  const result = await pool.query(
    `SELECT MAX(started_at) AS last_at
     FROM attendance_sessions
     WHERE subject_id = $1 AND status IN ('closed', 'expired', 'active')`,
    [subjectId],
  );
  return result.rows[0]?.last_at;
}

function evaluateRisk(stats, plan) {
  const maxAbsences = plan?.max_allowed_absences ?? 0;
  const held = stats.heldUnits;

  if (held < MIN_HELD_UNITS_BEFORE_ALERT) {
    return { atRisk: false, reason: 'insufficient_data' };
  }

  const alreadyBelow = stats.currentPct < THRESHOLD_PCT;
  const oneMoreDropsBelow = stats.currentPct >= THRESHOLD_PCT && stats.afterOneMoreAbsentPct < THRESHOLD_PCT;
  const absencesRemaining = Math.max(0, maxAbsences - stats.absentUnits);
  const nearAbsenceCap = absencesRemaining <= 1 && stats.currentPct >= THRESHOLD_PCT;

  const atRisk = alreadyBelow || oneMoreDropsBelow || nearAbsenceCap;

  return {
    atRisk,
    alreadyBelow,
    oneMoreDropsBelow,
    absencesRemaining,
    maxAbsences,
  };
}

async function getAtRiskStudentsForSubject(subjectId) {
  const plan = await getSubjectPlan(subjectId);
  if (!plan?.planned_session_count) return { plan: null, students: [] };

  const enrolled = await pool.query(
    `SELECT u.id AS student_id, u.full_name, u.student_id AS student_code
     FROM class_enrollments ce
     JOIN subjects s ON s.class_id = ce.class_id
     JOIN users u ON u.id = ce.student_id
     WHERE s.id = $1 AND u.role = 'student'
     ORDER BY u.full_name`,
    [subjectId],
  );

  const students = [];
  for (const row of enrolled.rows) {
    const stats = await getStudentSubjectStats(row.student_id, subjectId);
    const risk = evaluateRisk(stats, plan);
    if (risk.atRisk) {
      students.push({
        studentId: row.student_id,
        studentName: row.full_name,
        studentCode: row.student_code,
        currentPct: stats.currentPct,
        afterOneMoreAbsentPct: stats.afterOneMoreAbsentPct,
        absentUnits: stats.absentUnits,
        heldUnits: stats.heldUnits,
        absencesRemaining: risk.absencesRemaining,
        alreadyBelow: risk.alreadyBelow,
        oneMoreDropsBelow: risk.oneMoreDropsBelow,
      });
    }
  }

  students.sort((a, b) => a.currentPct - b.currentPct);
  return { plan, students };
}

async function buildPlanPayload(subjectId) {
  const plan = await getSubjectPlan(subjectId);
  if (!plan) return null;

  const { students: atRisk } = await getAtRiskStudentsForSubject(subjectId);
  const lastSessionAt = await getLastSessionAt(subjectId);

  return {
    subjectId,
    subjectName: plan.name,
    semesterTotalHours: plan.semester_total_hours,
    hoursPerWeek: plan.hours_per_week != null ? Number(plan.hours_per_week) : null,
    plannedSessionCount: plan.planned_session_count,
    maxAllowedAbsences: plan.max_allowed_absences,
    extraClassesRecorded: plan.extra_classes_recorded ?? 0,
    cancelledClassesRecorded: plan.cancelled_classes_recorded ?? 0,
    thresholdPct: THRESHOLD_PCT,
    atRiskCount: atRisk.length,
    atRiskStudents: atRisk,
    lastSessionAt,
    configured: !!(plan.planned_session_count && plan.semester_total_hours),
  };
}

module.exports = {
  THRESHOLD_PCT,
  computePlanFromHours,
  getSubjectPlan,
  upsertSubjectPlan,
  recordPlanAdjustment,
  getStudentSubjectStats,
  getAtRiskStudentsForSubject,
  buildPlanPayload,
  evaluateRisk,
  formatNextSessionHint,
  getLastSessionAt,
};
