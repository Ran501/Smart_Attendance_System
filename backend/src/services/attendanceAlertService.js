const pool = require('../database/pool');
const { sendToUser } = require('./notificationService');

const MIN_SESSIONS_BEFORE_ALERT = 10;
const THRESHOLD_PCT = 90;

/**
 * Calculate a student's attendance % for a subject, then send alerts if needed.
 * Called after a session closes or a teacher manually changes a status.
 */
async function checkAndAlertStudent(studentId, subjectId) {
  // Count total sessions held for this subject (closed or expired — finalised)
  const totalResult = await pool.query(
    `SELECT COUNT(*)::int AS total
     FROM attendance_sessions
     WHERE subject_id = $1 AND status IN ('closed', 'expired')`,
    [subjectId],
  );
  const total = totalResult.rows[0]?.total ?? 0;

  // Not enough sessions yet — skip
  if (total <= MIN_SESSIONS_BEFORE_ALERT) return;

  // Count sessions where the student was present or late
  const attendedResult = await pool.query(
    `SELECT COUNT(ar.id)::int AS attended
     FROM attendance_sessions s
     LEFT JOIN attendance_records ar
       ON ar.session_id = s.id AND ar.student_id = $1
          AND ar.status IN ('PRESENT', 'LATE')
     WHERE s.subject_id = $2 AND s.status IN ('closed', 'expired')`,
    [studentId, subjectId],
  );
  const attended = attendedResult.rows[0]?.attended ?? 0;

  const currentPct = (attended / total) * 100;
  const nextPct = (attended / (total + 1)) * 100;

  let type, title, body;

  if (currentPct < THRESHOLD_PCT) {
    // Already below 90%
    type = 'ATTENDANCE_DANGER';
    title = 'Attendance Below 90%';
    body = `Your attendance has dropped to ${currentPct.toFixed(1)}% — you are already below the 90% requirement.`;
  } else if (nextPct < THRESHOLD_PCT) {
    // One more absence will drop below 90%
    type = 'ATTENDANCE_WARNING';
    title = 'Attendance Warning';
    body = `One more absence will drop your attendance to ${nextPct.toFixed(1)}% — below the 90% requirement.`;
  } else {
    return; // Student is safe — no alert needed
  }

  // Get subject name for the message
  const subjectResult = await pool.query(
    'SELECT name FROM subjects WHERE id = $1',
    [subjectId],
  );
  const subjectName = subjectResult.rows[0]?.name ?? 'your module';
  body = `${subjectName}: ${body}`;

  const data = { subjectId, currentPct: currentPct.toFixed(1), nextPct: nextPct.toFixed(1) };

  // Notify the student
  await sendToUser(studentId, { type, title, body, data });

  // Notify the module teacher
  await alertTeacher(subjectId, studentId, subjectName, currentPct, nextPct, type);
}

async function alertTeacher(subjectId, studentId, subjectName, currentPct, nextPct, alertType) {
  const teacherResult = await pool.query(
    'SELECT teacher_id FROM subjects WHERE id = $1',
    [subjectId],
  );
  const teacherId = teacherResult.rows[0]?.teacher_id;
  if (!teacherId) return;

  const studentResult = await pool.query(
    'SELECT full_name FROM users WHERE id = $1',
    [studentId],
  );
  const studentName = studentResult.rows[0]?.full_name ?? 'A student';

  const isDanger = alertType === 'ATTENDANCE_DANGER';
  const title = isDanger ? `Attendance Alert — ${subjectName}` : `Attendance Warning — ${subjectName}`;
  const body = isDanger
    ? `${studentName} is at ${currentPct.toFixed(1)}% — already below the 90% requirement.`
    : `${studentName} is at ${currentPct.toFixed(1)}% — one more absence will drop them below 90%.`;

  await sendToUser(teacherId, {
    type: `TEACHER_${alertType}`,
    title,
    body,
    data: { subjectId, studentId, currentPct: currentPct.toFixed(1), nextPct: nextPct.toFixed(1) },
  });
}

/**
 * Run alerts for ALL enrolled students in a subject.
 * Called when a session is closed.
 */
async function checkAllStudentsForSubject(subjectId) {
  const enrolled = await pool.query(
    `SELECT ce.student_id
     FROM class_enrollments ce
     JOIN subjects s ON s.class_id = ce.class_id
     WHERE s.id = $1`,
    [subjectId],
  );

  await Promise.allSettled(
    enrolled.rows.map((row) => checkAndAlertStudent(row.student_id, subjectId)),
  );
}

module.exports = { checkAndAlertStudent, checkAllStudentsForSubject };
