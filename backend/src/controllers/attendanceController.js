const pool = require('../database/pool');
const config = require('../config');
const { isInsideGeoFence, checkHostProximity, distanceMeters } = require('../utils/geo');
const { evaluateFaceMatch } = require('../utils/face');
const { logAudit, logFraud } = require('../services/auditService');
const { expireStaleSessions } = require('./sessionController');
const { buildStudentModules } = require('./moduleController');

const EDITABLE_STATUSES = new Set([
  'PRESENT',
  'LATE',
  'ABSENT',
  'REJECTED',
  'MEDICAL_LEAVE',
  'OFFICIAL_LEAVE',
]);

function normalizeStatus(value) {
  const raw = String(value || '').trim().toUpperCase().replace(/[\s-]+/g, '_');
  if (raw === 'MEDICAL' || raw === 'ML') return 'MEDICAL_LEAVE';
  if (raw === 'OFFICIAL' || raw === 'OL') return 'OFFICIAL_LEAVE';
  return raw;
}

async function submitAttendance(req, res) {
  await expireStaleSessions();
  const {
    sessionId,
    sessionToken,
    liveEmbedding,
    latitude,
    longitude,
    wifiSsid,
    wifiBssid,
    deviceId,
    deviceFingerprint,
    livenessPassed,
    livenessScore,
    locationAccuracy,
  } = req.body;

  if (!Array.isArray(liveEmbedding) || liveEmbedding.length < 64) {
    console.error('[attendance] REJECTED: liveEmbedding missing or invalid', {
      type: typeof liveEmbedding,
      length: Array.isArray(liveEmbedding) ? liveEmbedding.length : 'N/A',
    });
    return res.status(400).json({
      accepted: false,
      reason: 'Face embedding missing or invalid — ensure face model is loaded on device',
    });
  }

  const sessionResult = await pool.query(
    `SELECT s.*, cr.latitude as room_lat, cr.longitude as room_lon,
            cr.radius_meters as room_radius_meters,
            cr.allowed_wifi_ssid, cr.allowed_wifi_bssid, cr.allowed_subnet,
            COALESCE(s.session_units, 1) AS session_units
     FROM attendance_sessions s
     LEFT JOIN classrooms cr ON cr.id = s.classroom_id
     WHERE s.id = $1 AND s.session_token = $2 AND s.status = 'active' AND s.ends_at > NOW()`,
    [sessionId, sessionToken],
  );
  if (!sessionResult.rows.length) {
    await logFraud(req.user.id, sessionId, 'INVALID_SESSION', {});
    return res.status(400).json({ accepted: false, reason: 'Session invalid or expired' });
  }
  const session = sessionResult.rows[0];

  const duplicate = await pool.query(
    `SELECT id, status FROM attendance_records WHERE session_id = $1 AND student_id = $2`,
    [sessionId, req.user.id],
  );
  if (duplicate.rows.length && duplicate.rows[0].status !== 'REJECTED') {
    return res.status(409).json({ accepted: false, reason: 'Attendance already marked' });
  }

  const enrolled = await pool.query(
    `SELECT 1 FROM class_enrollments WHERE class_id = $1 AND student_id = $2`,
    [session.class_id, req.user.id],
  );
  if (!enrolled.rows.length) {
    return res.status(403).json({ accepted: false, reason: 'You are not enrolled in this module/class' });
  }

  const device = await pool.query('SELECT * FROM devices WHERE user_id = $1', [req.user.id]);
  let deviceValid = false;
  if (device.rows.length === 0) {
    await pool.query(
      `INSERT INTO devices (user_id, device_id, device_fingerprint, device_name)
       VALUES ($1, $2, $3, 'Mobile Device')`,
      [req.user.id, deviceId, deviceFingerprint],
    );
    deviceValid = true;
  } else {
    deviceValid =
      device.rows[0].device_id === deviceId &&
      device.rows[0].device_fingerprint === deviceFingerprint;
  }
  if (!deviceValid) {
    await logFraud(req.user.id, sessionId, 'DEVICE_FAILED', { deviceId });
    await recordRejected(session, req.user.id, latitude, longitude, 0, {
      geoValid: false,
      wifiValid: false,
      deviceValid: false,
      livenessPassed: false,
      reason: 'Device verification failed',
    });
    return res.status(403).json({ accepted: false, reason: 'Device verification failed' });
  }

  const usesHostLocation = session.host_latitude != null && session.host_longitude != null;
  const centerLat = usesHostLocation ? session.host_latitude : session.room_lat;
  const centerLon = usesHostLocation ? session.host_longitude : session.room_lon;
  const baseRadius = usesHostLocation ? session.radius_meters : session.room_radius_meters ?? 30;

  let geoValid;
  let distToHost;
  let allowedRadius;

  if (usesHostLocation) {
    const proximity = checkHostProximity({
      studentLat: latitude,
      studentLon: longitude,
      hostLat: centerLat,
      hostLon: centerLon,
      baseRadius,
      hostAccuracy: session.host_accuracy,
      studentAccuracy: locationAccuracy,
    });
    geoValid = proximity.valid;
    distToHost = proximity.distance;
    allowedRadius = proximity.allowedRadius;
  } else {
    distToHost = distanceMeters(latitude, longitude, centerLat, centerLon);
    allowedRadius = baseRadius ?? 30;
    geoValid = isInsideGeoFence(latitude, longitude, {
      latitude: centerLat,
      longitude: centerLon,
      radius_meters: allowedRadius,
    });
  }

  if (!geoValid) {
    await logFraud(req.user.id, sessionId, 'GEO_FENCE_FAILED', {
      latitude,
      longitude,
      distanceMeters: distToHost,
      allowedRadius,
    });
    await recordRejected(session, req.user.id, latitude, longitude, 0, {
      geoValid: false,
      wifiValid: false,
      deviceValid: true,
      livenessPassed: livenessPassed || false,
      reason: usesHostLocation
        ? `Too far from teacher (${Math.round(distToHost)}m, allowed ~${Math.round(allowedRadius)}m)`
        : 'Outside classroom geo-fence',
    });
    return res.status(403).json({
      accepted: false,
      reason: usesHostLocation
        ? `Too far from teacher (${Math.round(distToHost)}m away, allowed ~${Math.round(allowedRadius)}m — stand closer or wait for GPS to settle)`
        : 'Outside classroom area',
      distanceMeters: distToHost,
      allowedRadiusMeters: allowedRadius,
    });
  }

  let wifiValid = true;
  if (!usesHostLocation && session.allowed_wifi_ssid) {
    wifiValid =
      wifiSsid === session.allowed_wifi_ssid ||
      (session.allowed_wifi_bssid && wifiBssid === session.allowed_wifi_bssid);
  }
  if (!wifiValid) {
    await logFraud(req.user.id, sessionId, 'WIFI_FAILED', { wifiSsid });
    await recordRejected(session, req.user.id, latitude, longitude, 0, {
      geoValid: true,
      wifiValid: false,
      deviceValid: true,
      livenessPassed: livenessPassed || false,
      reason: 'Not on approved campus WiFi',
    });
    return res.status(403).json({ accepted: false, reason: 'WiFi validation failed' });
  }

  if (!livenessPassed) {
    await logFraud(req.user.id, sessionId, 'LIVENESS_FAILED', { livenessScore });
    await recordRejected(session, req.user.id, latitude, longitude, 0, {
      geoValid: true,
      wifiValid: true,
      deviceValid: true,
      livenessPassed: false,
      reason: 'Liveness detection failed',
    });
    return res.status(403).json({ accepted: false, reason: 'Liveness verification failed' });
  }

  const stored = await pool.query(
    `SELECT id, angle_type, embedding FROM face_embeddings WHERE user_id = $1`,
    [req.user.id],
  );
  if (!stored.rows.length) {
    return res.status(400).json({
      accepted: false,
      reason: 'Face not registered. Complete smile, up, down, right, and left enrolment first.',
    });
  }

  if (stored.rows.length < 1) {
    return res.status(400).json({
      accepted: false,
      reason: 'Face not registered. Complete smile, up, down, right, and left enrolment first.',
    });
  }

  const storedEmbeddings = stored.rows.map((row) => ({
    id: row.id,
    angleType: row.angle_type,
    embedding:
      typeof row.embedding === 'string' ? JSON.parse(row.embedding) : row.embedding,
  }));

  const threshold = config.faceMatchThreshold;
  const faceMatch = evaluateFaceMatch(liveEmbedding, storedEmbeddings, threshold);
  const matchScore = faceMatch.similarity;
  if (!faceMatch.matched) {
    await logFraud(req.user.id, sessionId, 'FACE_MISMATCH', {
      confidence: matchScore,
      matchMode: faceMatch.matchMode,
      minSimilarity: faceMatch.minSimilarity,
    });
    await recordRejected(session, req.user.id, latitude, longitude, matchScore, {
      geoValid: true,
      wifiValid: true,
      deviceValid: true,
      livenessPassed: true,
      reason: `Face match below threshold (${(matchScore * 100).toFixed(1)}%)`,
    });
    return res.status(403).json({
      accepted: false,
      reason:
        `Face not recognized (${(matchScore * 100).toFixed(1)}%, ` +
        `need ${(threshold * 100).toFixed(0)}% or higher)`,
      confidence: matchScore,
      matchMode: faceMatch.matchMode,
      minSimilarity: faceMatch.minSimilarity,
    });
  }

  const status = 'PRESENT';
  await pool.query(
    `INSERT INTO attendance_records
     (session_id, class_id, student_id, status, match_confidence, latitude, longitude,
      geo_valid, wifi_valid, device_valid, liveness_passed)
     VALUES ($1, $2, $3, $4, $5, $6, $7, true, true, true, true)
     ON CONFLICT (session_id, student_id) DO UPDATE SET
       status = EXCLUDED.status,
       match_confidence = EXCLUDED.match_confidence,
       latitude = EXCLUDED.latitude,
       longitude = EXCLUDED.longitude,
       geo_valid = EXCLUDED.geo_valid,
       wifi_valid = EXCLUDED.wifi_valid,
       device_valid = EXCLUDED.device_valid,
       liveness_passed = EXCLUDED.liveness_passed,
       rejection_reason = NULL,
       manual_note = NULL,
       updated_at = NOW()`,
    [
      sessionId,
      session.class_id,
      req.user.id,
      status,
      matchScore,
      latitude,
      longitude,
    ],
  );

  await logAudit(req.user.id, 'ATTENDANCE_MARKED', 'attendance_record', sessionId, {
    confidence: matchScore,
    matchMode: faceMatch.matchMode,
  });

  if (req.io) {
    req.io.to(`session:${sessionId}`).emit('attendance:marked', {
      sessionId,
      studentId: req.user.id,
      status,
      confidence: matchScore,
    });
  }

  res.json({
    accepted: true,
    status,
    confidence: matchScore,
    matchMode: faceMatch.matchMode,
    threshold,
    message: 'Attendance recorded successfully',
  });
}

async function recordRejected(session, studentId, lat, lon, confidence, meta) {
  await pool.query(
    `INSERT INTO attendance_records
     (session_id, class_id, student_id, status, match_confidence, latitude, longitude,
      geo_valid, wifi_valid, device_valid, liveness_passed, rejection_reason)
     VALUES ($1, $2, $3, 'REJECTED', $4, $5, $6, $7, $8, $9, $10, $11)
     ON CONFLICT (session_id, student_id) DO UPDATE SET
       status = 'REJECTED',
       match_confidence = EXCLUDED.match_confidence,
       latitude = EXCLUDED.latitude,
       longitude = EXCLUDED.longitude,
       geo_valid = EXCLUDED.geo_valid,
       wifi_valid = EXCLUDED.wifi_valid,
       device_valid = EXCLUDED.device_valid,
       liveness_passed = EXCLUDED.liveness_passed,
       rejection_reason = EXCLUDED.rejection_reason,
       updated_at = NOW()`,
    [
      session.id,
      session.class_id,
      studentId,
      confidence,
      lat,
      lon,
      meta.geoValid,
      meta.wifiValid,
      meta.deviceValid,
      meta.livenessPassed,
      meta.reason,
    ],
  );
}

async function getStudentHistory(req, res) {
  const result = await pool.query(
    `SELECT COALESCE(ar.id::text, CONCAT(s.id, '-', $1::text)) AS id,
            s.id as session_id, s.id as session_code, sub.name as subject_name, c.name as class_name,
            COALESCE(ar.status, 'ABSENT') AS status,
            ar.match_confidence, ar.rejection_reason,
            COALESCE(ar.marked_at, s.started_at) AS marked_at,
            COALESCE(s.session_units, 1) AS session_units
     FROM attendance_sessions s
     JOIN subjects sub ON sub.id = s.subject_id
     JOIN classes c ON c.id = s.class_id
     JOIN class_enrollments ce ON ce.class_id = s.class_id AND ce.student_id = $1
     LEFT JOIN attendance_records ar ON ar.session_id = s.id AND ar.student_id = $1
     WHERE s.started_at <= NOW()
     ORDER BY s.started_at DESC LIMIT 100`,
    [req.user.id],
  );
  res.json(result.rows);
}

async function getStudentStats(req, res) {
  const result = await pool.query(
    `SELECT
       COALESCE(SUM(COALESCE(s.session_units, 1)) FILTER (WHERE ar.status = 'PRESENT'), 0)::int as present,
       COALESCE(SUM(COALESCE(s.session_units, 1)) FILTER (WHERE ar.status = 'LATE'), 0)::int as late,
       COALESCE(SUM(COALESCE(s.session_units, 1)) FILTER (WHERE ar.status = 'REJECTED'), 0)::int as rejected,
       COALESCE(SUM(COALESCE(s.session_units, 1)) FILTER (WHERE ar.status = 'MEDICAL_LEAVE'), 0)::int as medical_leave,
       COALESCE(SUM(COALESCE(s.session_units, 1)) FILTER (WHERE ar.status = 'OFFICIAL_LEAVE'), 0)::int as official_leave,
       COALESCE(SUM(COALESCE(s.session_units, 1)) FILTER (WHERE COALESCE(ar.status, 'ABSENT') = 'ABSENT'), 0)::int as absent,
       COALESCE(SUM(COALESCE(s.session_units, 1)), 0)::int as total
     FROM attendance_sessions s
     JOIN class_enrollments ce ON ce.class_id = s.class_id AND ce.student_id = $1
     LEFT JOIN attendance_records ar ON ar.session_id = s.id AND ar.student_id = $1
     WHERE s.started_at <= NOW()`,
    [req.user.id],
  );
  const stats = result.rows[0];
  const total = parseInt(stats.total, 10) || 0;
  const present = parseInt(stats.present, 10) || 0;
  const absent = parseInt(stats.absent, 10) || 0;
  const medicalLeave = parseInt(stats.medical_leave, 10) || 0;
  const officialLeave = parseInt(stats.official_leave, 10) || 0;
  const absentRulePercentage = total > 0 ? ((total - absent) / total) * 100 : 0;
  const leaveRulePercentage = total > 0 ? ((total - absent - medicalLeave - officialLeave) / total) * 100 : 0;

  let modules = [];
  try {
    modules = await buildStudentModules(req.user.id);
  } catch (e) {
    console.warn('[attendance] Could not build per-module stats:', e.message);
  }

  res.json({
    present,
    late: parseInt(stats.late, 10) || 0,
    rejected: parseInt(stats.rejected, 10) || 0,
    absent,
    medicalLeave,
    officialLeave,
    total,
    percentage: total > 0 ? ((present / total) * 100).toFixed(1) : '0.0',
    absentRulePercentage: absentRulePercentage.toFixed(1),
    leaveRulePercentage: leaveRulePercentage.toFixed(1),
    safe: absentRulePercentage >= 90 && leaveRulePercentage >= 80,
    modules,
    moduleStats: modules,
  });
}

async function updateAttendanceStatus(req, res) {
  const recordId = req.params.recordId || req.body.recordId || req.body.attendanceId;
  const sessionId = req.params.sessionId || req.body.sessionId || req.body.session_id;
  const studentId = req.params.studentId || req.body.studentId || req.body.student_id;
  const status = normalizeStatus(req.body.status || req.body.attendanceStatus || req.body.attendance_status);
  const note = req.body.note || req.body.remarks || req.body.reason || null;

  if (!EDITABLE_STATUSES.has(status)) {
    return res.status(400).json({ error: 'Invalid attendance status' });
  }

  let target;
  if (recordId) {
    const existing = await pool.query(
      `SELECT ar.*, s.teacher_id
       FROM attendance_records ar
       JOIN attendance_sessions s ON s.id = ar.session_id
       WHERE ar.id = $1`,
      [recordId],
    );
    if (!existing.rows.length) return res.status(404).json({ error: 'Attendance record not found' });
    target = existing.rows[0];
  } else {
    if (!sessionId || !studentId) {
      return res.status(400).json({ error: 'sessionId and studentId are required' });
    }
    const session = await pool.query(
      `SELECT id AS session_id, class_id, teacher_id FROM attendance_sessions WHERE id = $1`,
      [sessionId],
    );
    if (!session.rows.length) return res.status(404).json({ error: 'Session not found' });

    // Flutter may send either the internal user UUID, student ID/CID, or email.
    const student = await pool.query(
      `SELECT id FROM users
       WHERE id::text = $1 OR student_id = $1 OR email = $1
       LIMIT 1`,
      [String(studentId)],
    );
    if (!student.rows.length) return res.status(404).json({ error: 'Student not found' });

    target = { ...session.rows[0], student_id: student.rows[0].id };
  }

  if (req.user.role === 'teacher' && target.teacher_id !== req.user.id) {
    return res.status(403).json({ error: 'You can only edit your own session records' });
  }

  const updated = await pool.query(
    `INSERT INTO attendance_records
     (session_id, class_id, student_id, status, marked_at, manual_note, updated_by, updated_at)
     VALUES ($1, $2, $3, $4, NOW(), $5, $6, NOW())
     ON CONFLICT (session_id, student_id) DO UPDATE SET
       status = EXCLUDED.status,
       manual_note = EXCLUDED.manual_note,
       updated_by = EXCLUDED.updated_by,
       updated_at = NOW(),
       rejection_reason = CASE WHEN EXCLUDED.status = 'REJECTED' THEN attendance_records.rejection_reason ELSE NULL END
     RETURNING *`,
    [
      target.session_id,
      target.class_id,
      target.student_id,
      status,
      note,
      req.user.id,
    ],
  );

  await logAudit(req.user.id, 'ATTENDANCE_STATUS_UPDATED', 'attendance_record', updated.rows[0].id, {
    sessionId: target.session_id,
    studentId: target.student_id,
    status,
    note,
  });

  if (req.io) {
    req.io.to(`session:${target.session_id}`).emit('attendance:updated', {
      sessionId: target.session_id,
      studentId: target.student_id,
      status,
      record: updated.rows[0],
    });
  }

  res.json({ message: 'Attendance status updated', record: updated.rows[0] });
}

module.exports = {
  submitAttendance,
  getStudentHistory,
  getStudentStats,
  updateAttendanceStatus,
};
