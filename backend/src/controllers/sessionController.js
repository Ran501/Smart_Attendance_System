const QRCode = require('qrcode');
const pool = require('../database/pool');
const config = require('../config');
const { generateSessionId, generateSessionToken } = require('../utils/sessionId');
const { distanceMeters, checkHostProximity, DEFAULT_HOST_RADIUS } = require('../utils/geo');
const { logAudit } = require('../services/auditService');

const DEFAULT_HOST_RADIUS_METERS = DEFAULT_HOST_RADIUS;

async function expireStaleSessions() {
  await pool.query(
    `UPDATE attendance_sessions SET status = 'expired'
     WHERE status = 'active' AND ends_at < NOW()`,
  );
}

async function createSession(req, res) {
  await expireStaleSessions();
  const {
    classId,
    subjectId,
    classroomId,
    durationMinutes,
    latitude,
    longitude,
    radiusMeters,
    accuracy,
  } = req.body;
  const duration = durationMinutes || config.defaultSessionDurationMinutes;
  const radius = radiusMeters ?? DEFAULT_HOST_RADIUS_METERS;
  const hostAccuracy = accuracy != null ? parseFloat(accuracy) : null;

  if (latitude == null || longitude == null) {
    return res.status(400).json({
      error: 'Teacher location is required. Enable GPS and try again.',
    });
  }

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
     (id, class_id, subject_id, teacher_id, classroom_id, session_token, duration_minutes, ends_at, qr_payload,
      host_latitude, host_longitude, radius_meters, host_accuracy)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)`,
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
      latitude,
      longitude,
      radius,
      hostAccuracy,
    ],
  );

  const classroom = await pool.query('SELECT * FROM classrooms WHERE id = $1', [classroomId]);

  await logAudit(req.user.id, 'SESSION_STARTED', 'attendance_session', sessionId);

  const sessionPayload = {
    sessionId,
    sessionToken,
    classId,
    subjectId,
    durationMinutes: duration,
    startedAt: new Date().toISOString(),
    endsAt: endsAt.toISOString(),
    hostLatitude: latitude,
    hostLongitude: longitude,
    radiusMeters: radius,
    className: null,
    subjectName: null,
  };

  if (req.io) {
    req.io.to(`session:${sessionId}`).emit('session:started', sessionPayload);
    req.io.to(`class:${classId}`).emit('session:started', sessionPayload);
  }

  res.status(201).json({
    sessionId,
    sessionToken,
    classId,
    subjectId,
    durationMinutes: duration,
    startedAt: sessionPayload.startedAt,
    endsAt: sessionPayload.endsAt,
    qrPayload,
    qrDataUrl,
    hostLatitude: latitude,
    hostLongitude: longitude,
    radiusMeters: radius,
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

async function updateSessionLocation(req, res) {
  const { sessionId } = req.params;
  const { latitude, longitude, accuracy } = req.body;
  if (latitude == null || longitude == null) {
    return res.status(400).json({ error: 'latitude and longitude required' });
  }
  const result = await pool.query(
    `UPDATE attendance_sessions
     SET host_latitude = $1, host_longitude = $2, host_accuracy = $3
     WHERE id = $4 AND teacher_id = $5 AND status = 'active' AND ends_at > NOW()
     RETURNING id, class_id`,
    [latitude, longitude, accuracy != null ? parseFloat(accuracy) : null, sessionId, req.user.id],
  );
  if (!result.rows.length) {
    return res.status(404).json({ error: 'Active session not found' });
  }
  if (req.io) {
    req.io.to(`class:${result.rows[0].class_id}`).emit('session:location-updated', {
      sessionId,
      latitude,
      longitude,
    });
  }
  res.json({ ok: true });
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

function mapSessionForClient(row) {
  const usesHost = row.host_latitude != null && row.host_longitude != null;
  const centerLat = usesHost ? row.host_latitude : row.room_lat;
  const centerLon = usesHost ? row.host_longitude : row.room_lon;
  const radius = usesHost
    ? row.radius_meters ?? DEFAULT_HOST_RADIUS_METERS
    : row.room_radius_meters ?? 30;
  return {
    ...row,
    latitude: centerLat,
    longitude: centerLon,
    radius_meters: radius,
    uses_host_location: usesHost,
  };
}

async function getStudentActiveSessions(req, res) {
  await expireStaleSessions();
  const studentLat = req.query.latitude != null ? parseFloat(req.query.latitude) : null;
  const studentLon = req.query.longitude != null ? parseFloat(req.query.longitude) : null;
  const studentAccuracy =
    req.query.accuracy != null ? parseFloat(req.query.accuracy) : null;

  const result = await pool.query(
    `SELECT s.id, s.class_id, s.subject_id, s.session_token, s.started_at, s.ends_at, s.status,
            s.host_latitude, s.host_longitude, s.radius_meters, s.host_accuracy,
            c.name AS class_name, sub.name AS subject_name, u.full_name AS teacher_name,
            (SELECT COUNT(*) FROM attendance_records ar
             WHERE ar.session_id = s.id AND ar.student_id = $1) AS already_marked
     FROM attendance_sessions s
     JOIN classes c ON c.id = s.class_id
     JOIN subjects sub ON sub.id = s.subject_id
     JOIN users u ON u.id = s.teacher_id
     JOIN class_enrollments ce ON ce.class_id = s.class_id AND ce.student_id = $1
     WHERE s.status = 'active' AND s.ends_at > NOW()
     ORDER BY s.started_at DESC`,
    [req.user.id],
  );

  const sessions = result.rows.map((row) => {
    const mapped = mapSessionForClient(row);
    let distMeters = null;
    let withinRadius = null;
    if (
      studentLat != null &&
      studentLon != null &&
      row.host_latitude != null &&
      row.host_longitude != null
    ) {
      const proximity = checkHostProximity({
        studentLat,
        studentLon,
        hostLat: row.host_latitude,
        hostLon: row.host_longitude,
        baseRadius: row.radius_meters,
        hostAccuracy: row.host_accuracy,
        studentAccuracy,
      });
      distMeters = proximity.distance;
      withinRadius = proximity.valid;
      mapped.allowed_radius_meters = proximity.allowedRadius;
    }
    return {
      ...mapped,
      distance_meters: distMeters,
      within_radius: withinRadius,
      already_marked: parseInt(row.already_marked, 10) > 0,
    };
  });

  const enrollments = await pool.query(
    `SELECT class_id FROM class_enrollments WHERE student_id = $1`,
    [req.user.id],
  );

  res.json({
    sessions,
    enrolledClassIds: enrollments.rows.map((r) => r.class_id),
  });
}

async function validateQr(req, res) {
  const { sessionId, sessionToken } = req.body;
  await expireStaleSessions();
  const result = await pool.query(
    `SELECT s.*, cr.latitude AS room_lat, cr.longitude AS room_lon,
            cr.radius_meters AS room_radius_meters,
            cr.allowed_wifi_ssid, cr.allowed_wifi_bssid, cr.allowed_subnet
     FROM attendance_sessions s
     LEFT JOIN classrooms cr ON cr.id = s.classroom_id
     WHERE s.id = $1 AND s.session_token = $2 AND s.status = 'active' AND s.ends_at > NOW()`,
    [sessionId, sessionToken],
  );
  if (!result.rows.length) {
    return res.status(400).json({ valid: false, error: 'Invalid or expired session' });
  }
  res.json({ valid: true, session: mapSessionForClient(result.rows[0]) });
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
  getStudentActiveSessions,
  getSession,
  updateSessionLocation,
  closeSession,
  validateQr,
  getSessionAttendance,
  expireStaleSessions,
  mapSessionForClient,
};
