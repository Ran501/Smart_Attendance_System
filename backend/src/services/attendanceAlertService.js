const pool = require('../database/pool');
const { sendToUser } = require('./notificationService');
const {
  getStudentSubjectStats,
  getAtRiskStudentsForSubject,
  getSubjectPlan,
  evaluateRisk,
  formatNextSessionHint,
  getLastSessionAt,
  THRESHOLD_PCT,
} = require('./attendancePlanService');

async function notifyStudent(studentId, subjectId, subjectName, stats, risk) {
  const lastAt = await getLastSessionAt(subjectId);
  const nextHint = formatNextSessionHint(lastAt);

  let type;
  let title;
  let body;

  if (risk.alreadyBelow) {
    type = 'ATTENDANCE_DANGER';
    title = `Warning — Module: ${subjectName}`;
    body =
      `Your attendance is at ${stats.currentPct.toFixed(1)}% — below the ${THRESHOLD_PCT}% requirement. ` +
      `Next session: ${nextHint}.`;
  } else {
    type = 'ATTENDANCE_WARNING';
    title = `Warning — Module: ${subjectName}`;
    body =
      `Your attendance is at ${stats.currentPct.toFixed(1)}%. One more absence will drop you below ${THRESHOLD_PCT}%. ` +
      `Next session: ${nextHint}.`;
  }

  await sendToUser(studentId, {
    type,
    title,
    body,
    data: {
      subjectId,
      subjectName,
      currentPct: stats.currentPct.toFixed(1),
      nextPct: stats.afterOneMoreAbsentPct.toFixed(1),
    },
  });
}

async function notifyTeacherBatch(subjectId, subjectName, atRiskStudents) {
  const teacherResult = await pool.query(
    'SELECT teacher_id FROM subjects WHERE id = $1',
    [subjectId],
  );
  const teacherId = teacherResult.rows[0]?.teacher_id;
  if (!teacherId || !atRiskStudents.length) return;

  const lastAt = await getLastSessionAt(subjectId);
  const lastLabel = lastAt
    ? new Date(lastAt).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })
    : 'today';
  const lastWord = lastLabel === new Date().toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })
    ? 'today'
    : lastLabel;

  const names = atRiskStudents
    .slice(0, 8)
    .map((s) => `${s.studentName} (${s.currentPct.toFixed(1)}%)`)
    .join(', ');
  const more = atRiskStudents.length > 8 ? ` +${atRiskStudents.length - 8} more` : '';

  const title = `Attendance Alert — ${subjectName}`;
  const body =
    `${atRiskStudents.length} student${atRiskStudents.length === 1 ? '' : 's'} ` +
    `are at risk of falling below ${THRESHOLD_PCT}%: ${names}${more}. Last session: ${lastWord}.`;

  await sendToUser(teacherId, {
    type: 'TEACHER_ATTENDANCE_ALERT',
    title,
    body,
    data: {
      subjectId,
      count: String(atRiskStudents.length),
    },
  });
}

async function checkAndAlertStudent(studentId, subjectId) {
  const plan = await getSubjectPlan(subjectId);
  if (!plan?.planned_session_count) return;

  const subjectName = plan.name || 'your module';
  const stats = await getStudentSubjectStats(studentId, subjectId);
  const risk = evaluateRisk(stats, plan);
  if (!risk.atRisk) return;

  await notifyStudent(studentId, subjectId, subjectName, stats, risk);
}

async function checkAllStudentsForSubject(subjectId) {
  const plan = await getSubjectPlan(subjectId);
  if (!plan?.planned_session_count) return;

  const subjectName = plan.name || 'Module';
  const { students: atRisk } = await getAtRiskStudentsForSubject(subjectId);

  await Promise.allSettled(
    atRisk.map((s) =>
      notifyStudent(s.studentId, subjectId, subjectName, {
        currentPct: s.currentPct,
        afterOneMoreAbsentPct: s.afterOneMoreAbsentPct,
      }, {
        alreadyBelow: s.alreadyBelow,
        oneMoreDropsBelow: s.oneMoreDropsBelow,
      }),
    ),
  );

  if (atRisk.length > 0) {
    await notifyTeacherBatch(subjectId, subjectName, atRisk);
  }
}

module.exports = { checkAndAlertStudent, checkAllStudentsForSubject };
