const QRCode = require('qrcode');
const pool = require('../database/pool');
const config = require('../config');
const { generateSessionId, generateSessionToken } = require('../utils/sessionId');
const { checkHostProximity, DEFAULT_HOST_RADIUS } = require('../utils/geo');
const { logAudit } = require('../services/auditService');

const DEFAULT_HOST_RADIUS_METERS = DEFAULT_HOST_RADIUS;

function intInRange(value, min, max, fallback) {
  const parsed = parseInt(value, 10);
  if (Number.isNaN(parsed)) return fallback;
  return Math.min(Math.max(parsed, min), max);
}

function statusLabel(status) {
  if (!status) return 'ABSENT';
  const upper = String(status).toUpperCase().replace(/\s+/g, '_');
  if (upper === 'MEDICAL' || upper === 'MEDICAL_LEAVE' || upper === 'ML') return 'MEDICAL_LEAVE';
  if (upper === 'OFFICIAL' || upper === 'OFFICIAL_LEAVE' || upper === 'OL') return 'OFFICIAL_LEAVE';
  return upper;
}

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
  const sessionUnits = intInRange(
    req.body.sessionUnits ?? req.body.session_units ?? req.body.periodCount ?? req.body.blockPeriods,
    1,
    3,
    1,
  );

  if (latitude == null || longitude == null) {
    return res.status(400).json({
      error: 'Teacher location is required. Enable GPS and try again.',
    });
  }

  const subject = await pool.query(
    'SELECT code, name, class_id FROM subjects WHERE id = $1',
    [subjectId],
  );
  if (!subject.rows.length) {
    return res.status(404).json({ error: 'Module/subject not found' });
  }
  if (subject.rows[0].class_id !== classId && req.user.role !== 'admin') {
    return res.status(400).json({ error: 'Module does not belong to selected class' });
  }

  const sessionId = await generateSessionId(classId, subject.rows[0]?.code || classId);
  const sessionToken = generateSessionToken();
  const endsAt = new Date(Date.now() + duration * 60 * 1000);

  const qrPayload = JSON.stringify({
    sessionId,
    sessionToken,
    classId,
    subjectId,
    sessionUnits,
    expiresAt: endsAt.toISOString(),
  });
  const qrDataUrl = await QRCode.toDataURL(qrPayload);

  await pool.query(
    `INSERT INTO attendance_sessions
     (id, class_id, subject_id, teacher_id, classroom_id, session_token, duration_minutes, session_units,
      ends_at, qr_payload, host_latitude, host_longitude, radius_meters, host_accuracy)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)`,
    [
      sessionId,
      classId,
      subjectId,
      req.user.id,
      classroomId,
      sessionToken,
      duration,
      sessionUnits,
      endsAt,
      qrPayload,
      latitude,
      longitude,
      radius,
      hostAccuracy,
    ],
  );

  const classroom = await pool.query('SELECT * FROM classrooms WHERE id = $1', [classroomId]);
  const classResult = await pool.query('SELECT name FROM classes WHERE id = $1', [classId]);

  await logAudit(req.user.id, 'SESSION_STARTED', 'attendance_session', sessionId, {
    sessionUnits,
    classId,
    subjectId,
  });

  const sessionPayload = {
    id: sessionId,
    sessionId,
    sessionToken,
    classId,
    class_id: classId,
    subjectId,
    subject_id: subjectId,
    durationMinutes: duration,
    duration_minutes: duration,
    sessionUnits,
    session_units: sessionUnits,
    startedAt: new Date().toISOString(),
    endsAt: endsAt.toISOString(),
    hostLatitude: latitude,
    hostLongitude: longitude,
    radiusMeters: radius,
    className: classResult.rows[0]?.name || classId,
    class_name: classResult.rows[0]?.name || classId,
    subjectName: subject.rows[0]?.name || subjectId,
    subject_name: subject.rows[0]?.name || subjectId,
  };

  if (req.io) {
    req.io.to(`session:${sessionId}`).emit('session:started', sessionPayload);
    req.io.to(`class:${classId}`).emit('session:started', sessionPayload);
  }

  res.status(201).json({
    ...sessionPayload,
    status: 'active',
    started_at: sessionPayload.startedAt,
    ends_at: sessionPayload.endsAt,
    qrPayload,
    qr_payload: qrPayload,
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
            COALESCE(s.session_units, 1) AS session_units,
            COALESCE(s.session_units, 1) AS "sessionUnits",
            COUNT(ar.id) FILTER (WHERE ar.status = 'PRESENT') as present_count,
            COUNT(ar.id) FILTER (WHERE ar.status = 'REJECTED') as rejected_count
     FROM attendance_sessions s
     JOIN classes c ON c.id = s.class_id
     JOIN subjects sub ON sub.id = s.subject_id
     LEFT JOIN attendance_records ar ON ar.session_id = s.id
     WHERE s.teacher_id = $1 AND s.status = 'active' AND s.ends_at > NOW()
     GROUP BY s.id, c.name, sub.name
     ORDER BY s.started_at DESC`,
    [req.user.id],
  );
  res.json(result.rows);
}

async function getSession(req, res) {
  const { sessionId } = req.params;
  const result = await pool.query(
    `SELECT s.*, c.name as class_name, sub.name as subject_name,
            cr.name as classroom_name, cr.latitude AS room_lat, cr.longitude AS room_lon,
            cr.radius_meters AS room_radius_meters, cr.allowed_wifi_ssid, cr.allowed_wifi_bssid,
            COALESCE(s.session_units, 1) AS session_units,
            COALESCE(s.session_units, 1) AS "sessionUnits"
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
    sessionUnits: row.session_units ?? row.sessionUnits ?? 1,
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
            COALESCE(s.session_units, 1) AS session_units,
            c.name AS class_name, sub.name AS subject_name, u.full_name AS teacher_name,
            (SELECT COUNT(*) FROM attendance_records ar
             WHERE ar.session_id = s.id AND ar.student_id = $1 AND ar.status <> 'REJECTED') AS already_marked
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
            cr.allowed_wifi_ssid, cr.allowed_wifi_bssid, cr.allowed_subnet,
            COALESCE(s.session_units, 1) AS session_units
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
  if (String(req.query.includeAll).toLowerCase() === 'true') {
    return getSessionRoster(req, res);
  }
  const { sessionId } = req.params;
  const records = await pool.query(
    `SELECT ar.*, u.full_name, u.student_id as student_code, u.email,
            ar.student_id AS user_id
     FROM attendance_records ar
     JOIN users u ON u.id = ar.student_id
     WHERE ar.session_id = $1 ORDER BY u.full_name`,
    [sessionId],
  );
  res.json(records.rows);
}

async function getSessionRoster(req, res) {
  const { sessionId } = req.params;
  const session = await pool.query(
    `SELECT s.*, COALESCE(s.session_units, 1) AS session_units
     FROM attendance_sessions s
     WHERE s.id = $1`,
    [sessionId],
  );
  if (!session.rows.length) {
    return res.status(404).json({ error: 'Session not found' });
  }
  const row = session.rows[0];

  if (req.user.role === 'teacher' && row.teacher_id !== req.user.id) {
    return res.status(403).json({ error: 'You can only view your own session roster' });
  }

  const records = await pool.query(
    `SELECT u.id AS user_id, u.id AS student_uuid, u.full_name, u.student_id AS student_code,
            u.student_id, u.email, ar.id AS record_id, ar.id,
            COALESCE(ar.status, 'ABSENT') AS status,
            ar.match_confidence, ar.geo_valid, ar.wifi_valid, ar.device_valid,
            ar.liveness_passed, ar.rejection_reason, ar.manual_note,
            ar.marked_at, ar.updated_at,
            $2::int AS session_units
     FROM class_enrollments ce
     JOIN users u ON u.id = ce.student_id
     LEFT JOIN attendance_records ar ON ar.session_id = $1 AND ar.student_id = u.id
     WHERE ce.class_id = $3 AND u.role = 'student'
     ORDER BY u.full_name`,
    [sessionId, row.session_units || 1, row.class_id],
  );

  const rows = records.rows.map((r) => ({
    ...r,
    studentId: r.student_uuid,
    studentCode: r.student_code,
    student_name: r.full_name,
    studentName: r.full_name,
    attendance_status: statusLabel(r.status),
    attendanceStatus: statusLabel(r.status),
  }));

  res.json(rows);
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
  getSessionRoster,
  expireStaleSessions,
  mapSessionForClient,
};
