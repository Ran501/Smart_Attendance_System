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

const ALERT_COOLDOWN_HOURS = 4;

async function wasRecentlyNotified(userId, subjectId, types) {
  const result = await pool.query(
    `SELECT 1 FROM notifications
     WHERE user_id = $1
       AND type = ANY($2::text[])
       AND (data->>'subjectId') = $3
       AND created_at > NOW() - ($4::int * INTERVAL '1 hour')
     LIMIT 1`,
    [userId, types, String(subjectId), ALERT_COOLDOWN_HOURS],
  );
  return result.rows.length > 0;
}

async function notifyStudent(studentId, subjectId, subjectName, stats, risk) {
  const lastAt = await getLastSessionAt(subjectId);
  const nextHint = formatNextSessionHint(lastAt);

  const type = risk.alreadyBelow ? 'ATTENDANCE_DANGER' : 'ATTENDANCE_WARNING';
  const title = `Warning — Module: ${subjectName}`;
  const body = risk.alreadyBelow
    ? `Your attendance is at ${stats.currentPct.toFixed(1)}% — below the ${THRESHOLD_PCT}% requirement. Next session: ${nextHint}.`
    : `Your attendance is at ${stats.currentPct.toFixed(1)}%. One more absence will drop you below ${THRESHOLD_PCT}%. Next session: ${nextHint}.`;

  const types = [type, 'ATTENDANCE_WARNING', 'ATTENDANCE_DANGER'];
  if (await wasRecentlyNotified(studentId, subjectId, types)) return false;

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
  return true;
}

async function notifyTeacherBatch(subjectId, subjectName, atRiskStudents) {
  const teacherResult = await pool.query(
    'SELECT teacher_id FROM subjects WHERE id = $1',
    [subjectId],
  );
  const teacherId = teacherResult.rows[0]?.teacher_id;
  if (!teacherId || !atRiskStudents.length) return false;

  if (await wasRecentlyNotified(teacherId, subjectId, ['TEACHER_ATTENDANCE_ALERT'])) {
    return false;
  }

  const lastAt = await getLastSessionAt(subjectId);
  const todayLabel = new Date().toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
  const lastLabel = lastAt
    ? new Date(lastAt).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })
    : 'today';
  const lastWord = lastLabel === todayLabel ? 'today' : lastLabel;

  const names = atRiskStudents
    .slice(0, 8)
    .map((s) => `${s.studentName} (${s.currentPct.toFixed(1)}%)`)
    .join(', ');
  const more = atRiskStudents.length > 8 ? ` +${atRiskStudents.length - 8} more` : '';

  const title = `Attendance Alert — ${subjectName}`;
  const body =
    `${atRiskStudents.length} student${atRiskStudents.length === 1 ? '' : 's'} ` +
    `are below or at risk of falling below ${THRESHOLD_PCT}%: ${names}${more}. Last session: ${lastWord}.`;

  await sendToUser(teacherId, {
    type: 'TEACHER_ATTENDANCE_ALERT',
    title,
    body,
    data: {
      subjectId,
      count: String(atRiskStudents.length),
    },
  });
  return true;
}

async function checkAndAlertStudent(studentId, subjectId) {
  const plan = await getSubjectPlan(subjectId);
  const subjectName = plan?.name || 'your module';
  const stats = await getStudentSubjectStats(studentId, subjectId);
  const risk = evaluateRisk(stats, plan || {});
  if (!risk.atRisk) return;

  await notifyStudent(studentId, subjectId, subjectName, stats, risk);
}

async function checkAllStudentsForSubject(subjectId) {
  const plan = await getSubjectPlan(subjectId);
  const subjectName = plan?.name || 'Module';
  const { students: atRisk } = await getAtRiskStudentsForSubject(subjectId);
  if (!atRisk.length) return;

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

  await notifyTeacherBatch(subjectId, subjectName, atRisk);
}

module.exports = {
  checkAndAlertStudent,
  checkAllStudentsForSubject,
};
