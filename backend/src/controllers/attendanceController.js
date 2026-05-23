const pool = require('../database/pool');
const config = require('../config');
const { validateBleProximity } = require('../utils/ble');
const { upsertAttendanceRecord, setAttendanceStatus } = require('../utils/dbCompat');
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
    bleVerified,
    bleRssi,
    bleDeviceId,
    bleDeviceName,
    deviceId,
    deviceFingerprint,
    livenessPassed,
    livenessScore,
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
    `SELECT s.*, COALESCE(s.session_units, 1) AS session_units
     FROM attendance_sessions s
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
    await recordRejected(session, req.user.id, 0, {
      deviceValid: false,
      livenessPassed: false,
      bleVerified: false,
      bleRssi: null,
      reason: 'Device verification failed',
    });
    return res.status(403).json({ accepted: false, reason: 'Device verification failed' });
  }

  const bleCheck = validateBleProximity({ bleVerified, bleRssi });
  if (!bleCheck.valid) {
    await logFraud(req.user.id, sessionId, 'BLE_FAILED', {
      bleRssi,
      bleDeviceId,
      bleDeviceName,
    });
    await recordRejected(session, req.user.id, 0, {
      deviceValid: true,
      livenessPassed: livenessPassed || false,
      bleVerified: false,
      bleRssi: bleRssi != null ? Number(bleRssi) : null,
      reason: bleCheck.reason,
    });
    return res.status(403).json({ accepted: false, reason: bleCheck.reason });
  }

  if (!livenessPassed) {
    await logFraud(req.user.id, sessionId, 'LIVENESS_FAILED', { livenessScore });
    await recordRejected(session, req.user.id, 0, {
      deviceValid: true,
      livenessPassed: false,
      bleVerified: true,
      bleRssi: bleRssi != null ? Number(bleRssi) : null,
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
    await recordRejected(session, req.user.id, matchScore, {
      deviceValid: true,
      livenessPassed: true,
      bleVerified: true,
      bleRssi: bleRssi != null ? Number(bleRssi) : null,
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
  const rssiValue = bleRssi != null ? Number(bleRssi) : null;
  await upsertAttendanceRecord(pool, {
    sessionId,
    classId: session.class_id,
    studentId: req.user.id,
    status,
    confidence: matchScore,
    deviceValid: true,
    livenessPassed: true,
    rejectionReason: null,
    bleVerified: true,
    bleRssi: rssiValue,
  });

  await logAudit(req.user.id, 'ATTENDANCE_MARKED', 'attendance_record', sessionId, {
    confidence: matchScore,
    matchMode: faceMatch.matchMode,
    bleRssi: rssiValue,
  });

  if (req.io) {
    const markedPayload = {
      sessionId,
      classId: session.class_id,
      studentId: req.user.id,
      status,
      confidence: matchScore,
    };
    req.io.to(`session:${sessionId}`).emit('attendance:marked', markedPayload);
    req.io.to(`class:${session.class_id}`).emit('attendance:marked', markedPayload);
    req.io.to(`class:${session.class_id}`).emit('attendance:updated', markedPayload);
    req.io.to(`student:${req.user.id}`).emit('attendance:marked', markedPayload);
    req.io.to(`student:${req.user.id}`).emit('attendance:updated', markedPayload);
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

async function recordRejected(session, studentId, confidence, meta) {
  await upsertAttendanceRecord(pool, {
    sessionId: session.id,
    classId: session.class_id,
    studentId,
    status: 'REJECTED',
    confidence,
    deviceValid: meta.deviceValid,
    livenessPassed: meta.livenessPassed,
    rejectionReason: meta.reason,
    bleVerified: meta.bleVerified === true,
    bleRssi: meta.bleRssi,
  });
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
  try {
    const sessionId =
      req.params.sessionId || req.body.sessionId || req.body.session_id;
    let recordId =
      req.params.recordId ||
      req.body.recordId ||
      req.body.record_id ||
      req.body.attendanceId;
    let studentId =
      req.params.studentId || req.body.studentId || req.body.student_id;

    const status = normalizeStatus(req.body.status || req.body.attendanceStatus);
    if (!EDITABLE_STATUSES.has(status)) {
      return res.status(400).json({ error: 'Invalid attendance status' });
    }
    if (!sessionId) {
      return res.status(400).json({ error: 'sessionId required' });
    }

    const session = await pool.query(
      'SELECT id, class_id, teacher_id FROM attendance_sessions WHERE id = $1',
      [sessionId],
    );
    if (!session.rows.length) {
      return res.status(404).json({ error: 'Session not found' });
    }
    const classId = session.rows[0].class_id;
    if (req.user.role === 'teacher' && session.rows[0].teacher_id !== req.user.id) {
      return res.status(403).json({ error: 'Not your session' });
    }

    if (!studentId && recordId) {
      const existing = await pool.query(
        'SELECT student_id FROM attendance_records WHERE id = $1 AND session_id = $2',
        [recordId, sessionId],
      );
      if (existing.rows.length) {
        studentId = existing.rows[0].student_id;
      }
    }

    if (!recordId && !studentId) {
      return res.status(400).json({ error: 'recordId or studentId required' });
    }

    const row = await setAttendanceStatus(pool, {
      sessionId,
      classId,
      studentId,
      recordId,
      status,
      updatedBy: req.user.id,
    });

    if (!row) {
      return res.status(404).json({ error: 'Attendance record not found' });
    }

    const payload = {
      sessionId,
      classId,
      studentId: row.student_id || studentId,
      recordId: row.id || recordId,
      status,
    };

    if (req.io) {
      req.io.to(`session:${sessionId}`).emit('attendance:record-updated', payload);
      req.io.to(`class:${classId}`).emit('attendance:updated', payload);
      req.io.to(`class:${classId}`).emit('attendance:marked', payload);
      if (payload.studentId) {
        req.io.to(`student:${payload.studentId}`).emit('attendance:record-updated', payload);
        req.io.to(`student:${payload.studentId}`).emit('attendance:updated', payload);
      }
    }

    res.json({ ok: true, ...payload });
  } catch (err) {
    console.error('[attendance] updateAttendanceStatus failed:', err);
    res.status(500).json({
      error: err.message || 'Could not update attendance record',
    });
  }
}

module.exports = {
  submitAttendance,
  getStudentHistory,
  getStudentStats,
  updateAttendanceStatus,
};
