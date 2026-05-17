const pool = require('../database/pool');
const config = require('../config');
const { isInsideGeoFence, checkHostProximity, distanceMeters } = require('../utils/geo');
const { cosineSimilarity } = require('../utils/face');
const { logAudit, logFraud } = require('../services/auditService');
const { expireStaleSessions } = require('./sessionController');

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

  // ─── FIX: validate embedding immediately — null/missing = fail fast ────────
  if (!Array.isArray(liveEmbedding) || liveEmbedding.length < 192) {
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
            cr.allowed_wifi_ssid, cr.allowed_wifi_bssid, cr.allowed_subnet
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
    `SELECT id FROM attendance_records WHERE session_id = $1 AND student_id = $2`,
    [sessionId, req.user.id],
  );
  if (duplicate.rows.length) {
    return res.status(409).json({ accepted: false, reason: 'Attendance already marked' });
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

  const usesHostLocation =
    session.host_latitude != null && session.host_longitude != null;
  const centerLat = usesHostLocation ? session.host_latitude : session.room_lat;
  const centerLon = usesHostLocation ? session.host_longitude : session.room_lon;
  const baseRadius = usesHostLocation
    ? session.radius_meters
    : session.room_radius_meters ?? 30;

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

  // ─── FACE MATCHING ────────────────────────────────────────────────────────
  const stored = await pool.query(
    `SELECT id, angle_type, embedding FROM face_embeddings WHERE user_id = $1`,
    [req.user.id],
  );
  if (!stored.rows.length) {
    return res.status(400).json({ accepted: false, reason: 'Face not registered' });
  }

  // FIX: add detailed similarity logging so you can see scores in the terminal
  console.log('\n=== FACE MATCH DEBUG ===');
  console.log(`User: ${req.user.id}`);
  console.log(`Live embedding dims: ${liveEmbedding.length}`);
  console.log(`Live embedding sample: [${liveEmbedding.slice(0, 5).map(v => v.toFixed(4)).join(', ')}]`);
  console.log(`Stored embeddings: ${stored.rows.length}`);

  let bestSimilarity = 0;
  for (const row of stored.rows) {
    const emb = typeof row.embedding === 'string'
      ? JSON.parse(row.embedding)
      : row.embedding;
    const sim = cosineSimilarity(liveEmbedding, emb);
    console.log(`  [${row.angle_type}] dims: ${emb.length}, similarity: ${sim.toFixed(4)}`);
    if (sim > bestSimilarity) bestSimilarity = sim;
  }

  const threshold = config.faceMatchThreshold ?? 0.65;
  console.log(`Best similarity: ${bestSimilarity.toFixed(4)}`);
  console.log(`Threshold: ${threshold}`);
  console.log(`Result: ${bestSimilarity >= threshold ? '✅ MATCH' : '❌ NO MATCH'}`);
  console.log('========================\n');

  if (bestSimilarity < threshold) {
    await logFraud(req.user.id, sessionId, 'FACE_MISMATCH', { confidence: bestSimilarity });
    await recordRejected(session, req.user.id, latitude, longitude, bestSimilarity, {
      geoValid: true,
      wifiValid: true,
      deviceValid: true,
      livenessPassed: true,
      reason: `Face match below threshold (${(bestSimilarity * 100).toFixed(1)}%)`,
    });
    return res.status(403).json({
      accepted: false,
      reason: `Face not recognized (${(bestSimilarity * 100).toFixed(1)}% match, need ${(threshold * 100).toFixed(0)}%)`,
      confidence: bestSimilarity,
    });
  }

  const status = 'PRESENT';
  await pool.query(
    `INSERT INTO attendance_records
     (session_id, class_id, student_id, status, match_confidence, latitude, longitude,
      geo_valid, wifi_valid, device_valid, liveness_passed)
     VALUES ($1, $2, $3, $4, $5, $6, $7, true, true, true, true)`,
    [sessionId, session.class_id, req.user.id, status, bestSimilarity, latitude, longitude],
  );

  await logAudit(req.user.id, 'ATTENDANCE_MARKED', 'attendance_record', sessionId, {
    confidence: bestSimilarity,
  });

  if (req.io) {
    req.io.to(`session:${sessionId}`).emit('attendance:marked', {
      sessionId,
      studentId: req.user.id,
      status,
      confidence: bestSimilarity,
    });
  }

  res.json({
    accepted: true,
    status,
    confidence: bestSimilarity,
    message: 'Attendance recorded successfully',
  });
}

async function recordRejected(session, studentId, lat, lon, confidence, meta) {
  await pool.query(
    `INSERT INTO attendance_records
     (session_id, class_id, student_id, status, match_confidence, latitude, longitude,
      geo_valid, wifi_valid, device_valid, liveness_passed, rejection_reason)
     VALUES ($1, $2, $3, 'REJECTED', $4, $5, $6, $7, $8, $9, $10, $11)`,
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
    `SELECT ar.*, s.id as session_code, sub.name as subject_name, c.name as class_name
     FROM attendance_records ar
     JOIN attendance_sessions s ON s.id = ar.session_id
     JOIN subjects sub ON sub.id = s.subject_id
     JOIN classes c ON c.id = ar.class_id
     WHERE ar.student_id = $1
     ORDER BY ar.marked_at DESC LIMIT 100`,
    [req.user.id],
  );
  res.json(result.rows);
}

async function getStudentStats(req, res) {
  const result = await pool.query(
    `SELECT
       COUNT(*) FILTER (WHERE status = 'PRESENT') as present,
       COUNT(*) FILTER (WHERE status = 'LATE') as late,
       COUNT(*) FILTER (WHERE status = 'REJECTED') as rejected,
       COUNT(*) as total
     FROM attendance_records WHERE student_id = $1`,
    [req.user.id],
  );
  const stats = result.rows[0];
  const total = parseInt(stats.total, 10) || 0;
  const present = parseInt(stats.present, 10) || 0;
  res.json({
    present,
    late: parseInt(stats.late, 10) || 0,
    rejected: parseInt(stats.rejected, 10) || 0,
    total,
    percentage: total > 0 ? ((present / total) * 100).toFixed(1) : '0.0',
  });
}

module.exports = { submitAttendance, getStudentHistory, getStudentStats };