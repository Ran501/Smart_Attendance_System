const QRCode = require('qrcode');
const pool = require('../database/pool');
const config = require('../config');
const { generateSessionId, generateSessionToken } = require('../utils/sessionId');
const { logAudit } = require('../services/auditService');

async function expireStaleSessions() {
  await pool.query(
    `UPDATE attendance_sessions SET status = 'expired'
     WHERE status = 'active' AND ends_at < NOW()`,
  );
}

async function createSession(req, res) {
  await expireStaleSessions();
  const { classId, subjectId, classroomId, durationMinutes } = req.body;
  const duration = durationMinutes || config.defaultSessionDurationMinutes;

  const subject = await pool.query('SELECT code FROM subjects WHERE id = $1', [subjectId]);
  const sessionId = await generateSessionId(classId, subject.rows[0]?.code || classId);
  const sessionToken = generateSessionToken();
  const endsAt = new Date(Date.now() + duration * 60 * 1000);

  const qrPayload = JSON.stringify({
    sessionId,
    sessionToken,
    classId,
    subjectId,
    expiresAt: endsAt.toISOString(),
  });
  const qrDataUrl = await QRCode.toDataURL(qrPayload);

  await pool.query(
    `INSERT INTO attendance_sessions
     (id, class_id, subject_id, teacher_id, classroom_id, session_token, duration_minutes, ends_at, qr_payload)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
    [
      sessionId,
      classId,
      subjectId,
      req.user.id,
      classroomId,
      sessionToken,
      duration,
      endsAt,
      qrPayload,
    ],
  );

  const classroom = await pool.query('SELECT * FROM classrooms WHERE id = $1', [classroomId]);

  await logAudit(req.user.id, 'SESSION_STARTED', 'attendance_session', sessionId);

  if (req.io) {
    req.io.to(`session:${sessionId}`).emit('session:started', { sessionId, classId });
  }

  res.status(201).json({
    sessionId,
    sessionToken,
    classId,
    subjectId,
    durationMinutes: duration,
    startedAt: new Date().toISOString(),
    endsAt: endsAt.toISOString(),
    qrPayload,
    qrDataUrl,
    classroom: classroom.rows[0],
  });
}

async function getActiveSessions(req, res) {
  await expireStaleSessions();
  const result = await pool.query(
    `SELECT s.*, c.name as class_name, sub.name as subject_name,
            (SELECT COUNT(*) FROM attendance_records ar WHERE ar.session_id = s.id AND ar.status = 'PRESENT') as present_count
     FROM attendance_sessions s
     JOIN classes c ON c.id = s.class_id
     JOIN subjects sub ON sub.id = s.subject_id
     WHERE s.teacher_id = $1 AND s.status = 'active' AND s.ends_at > NOW()
     ORDER BY s.started_at DESC`,
    [req.user.id],
  );
  res.json(result.rows);
}

async function getSession(req, res) {
  const { sessionId } = req.params;
  const result = await pool.query(
    `SELECT s.*, c.name as class_name, sub.name as subject_name, cr.*
     FROM attendance_sessions s
     JOIN classes c ON c.id = s.class_id
     JOIN subjects sub ON sub.id = s.subject_id
     LEFT JOIN classrooms cr ON cr.id = s.classroom_id
     WHERE s.id = $1`,
    [sessionId],
  );
  if (!result.rows.length) {
    return res.status(404).json({ error: 'Session not found' });
  }
  res.json(result.rows[0]);
}

async function closeSession(req, res) {
  const { sessionId } = req.params;
  await pool.query(
    `UPDATE attendance_sessions SET status = 'closed', closed_at = NOW()
     WHERE id = $1 AND teacher_id = $2`,
    [sessionId, req.user.id],
  );
  if (req.io) {
    req.io.to(`session:${sessionId}`).emit('session:closed', { sessionId });
  }
  res.json({ message: 'Session closed' });
}

async function validateQr(req, res) {
  const { sessionId, sessionToken } = req.body;
  await expireStaleSessions();
  const result = await pool.query(
    `SELECT s.*, cr.latitude, cr.longitude, cr.radius_meters,
            cr.allowed_wifi_ssid, cr.allowed_wifi_bssid, cr.allowed_subnet
     FROM attendance_sessions s
     LEFT JOIN classrooms cr ON cr.id = s.classroom_id
     WHERE s.id = $1 AND s.session_token = $2 AND s.status = 'active' AND s.ends_at > NOW()`,
    [sessionId, sessionToken],
  );
  if (!result.rows.length) {
    return res.status(400).json({ valid: false, error: 'Invalid or expired session' });
  }
  res.json({ valid: true, session: result.rows[0] });
}

async function getSessionAttendance(req, res) {
  const { sessionId } = req.params;
  const records = await pool.query(
    `SELECT ar.*, u.full_name, u.student_id as student_code
     FROM attendance_records ar
     JOIN users u ON u.id = ar.student_id
     WHERE ar.session_id = $1 ORDER BY ar.marked_at`,
    [sessionId],
  );
  res.json(records.rows);
}

module.exports = {
  createSession,
  getActiveSessions,
  getSession,
  closeSession,
  validateQr,
  getSessionAttendance,
  expireStaleSessions,
};
