const pool = require('../database/pool');
const { logAudit, logFraud } = require('../services/auditService');
const { evaluateFaceMatch } = require('../utils/face');
const {
  prepareEmbedding,
  buildEnrollmentTemplate,
  validateEmbedding,
  FACE_PREPROCESS_SPEC,
} = require('../utils/facePreprocess');

const REQUIRED_REGISTRATION_ANGLES = ['smile', 'up', 'down', 'right', 'left'];
const TEMPLATE_ANGLE = 'template';

async function registerEmbeddings(req, res) {
  const { embeddings, deviceId } = req.body;
  if (!embeddings?.length) {
    return res.status(400).json({ error: 'At least one embedding required' });
  }

  const providedAngles = new Set(
    embeddings.map((e) => String(e.angleType || '').trim().toLowerCase()),
  );
  const missing = REQUIRED_REGISTRATION_ANGLES.filter((a) => !providedAngles.has(a));
  if (missing.length) {
    return res.status(400).json({
      error: `Complete all registration poses. Missing: ${missing.join(', ')}`,
      requiredAngles: REQUIRED_REGISTRATION_ANGLES,
    });
  }

  const poseVectors = [];
  try {
    for (const item of embeddings) {
      validateEmbedding(item.embedding);
      poseVectors.push(prepareEmbedding(item.embedding));
    }
  } catch (err) {
    return res.status(400).json({ error: err.message });
  }

  const template = buildEnrollmentTemplate(poseVectors);

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query('DELETE FROM face_embeddings WHERE user_id = $1', [req.user.id]);

    await client.query(
      `INSERT INTO face_embeddings (user_id, angle_type, embedding, device_id)
       VALUES ($1, $2, $3::jsonb, $4)`,
      [req.user.id, TEMPLATE_ANGLE, JSON.stringify(template), deviceId],
    );

    for (const item of embeddings) {
      const normalized = prepareEmbedding(item.embedding);
      await client.query(
        `INSERT INTO face_embeddings (user_id, angle_type, embedding, device_id)
         VALUES ($1, $2, $3::jsonb, $4)`,
        [
          req.user.id,
          String(item.angleType).trim().toLowerCase(),
          JSON.stringify(normalized),
          deviceId,
        ],
      );
    }

    await client.query('COMMIT');
    await logAudit(req.user.id, 'FACE_REGISTERED', 'face_embeddings', req.user.id, {
      poseCount: embeddings.length,
      dims: template.length,
      preprocessSpec: FACE_PREPROCESS_SPEC.version,
      enrollment: FACE_PREPROCESS_SPEC.enrollmentStrategy,
    });
    res.status(201).json({
      message: 'Face embeddings registered',
      count: embeddings.length,
      templateDims: template.length,
      preprocessSpec: FACE_PREPROCESS_SPEC.version,
      threshold: FACE_PREPROCESS_SPEC.defaultThreshold,
    });
  } catch (e) {
    await client.query('ROLLBACK');
    console.error('[faceController] registerEmbeddings error:', e);
    res.status(500).json({ error: 'Failed to register embeddings' });
  } finally {
    client.release();
  }
}

async function getMyEmbeddings(req, res) {
  const result = await pool.query(
    `SELECT id, angle_type, registered_at FROM face_embeddings WHERE user_id = $1`,
    [req.user.id],
  );
  const rows = result.rows;
  const hasTemplate = rows.some((r) => r.angle_type === TEMPLATE_ANGLE);
  const poseCount = rows.filter((r) => r.angle_type !== TEMPLATE_ANGLE).length;
  const registered = hasTemplate || poseCount >= REQUIRED_REGISTRATION_ANGLES.length;

  res.json({
    registered,
    hasTemplate,
    count: rows.length,
    poseCount,
    requiredCount: REQUIRED_REGISTRATION_ANGLES.length,
    preprocessSpec: FACE_PREPROCESS_SPEC.version,
    embeddings: rows,
  });
}

async function verifyEmbedding(req, res) {
  const { embedding, sessionId } = req.body;

  try {
    validateEmbedding(embedding);
  } catch (err) {
    return res.status(400).json({ error: err.message });
  }

  const result = await pool.query(
    `SELECT id, angle_type, embedding
     FROM face_embeddings
     WHERE user_id = $1`,
    [req.user.id],
  );

  if (result.rows.length === 0) {
    return res.status(404).json({ error: 'No registered face found for this user' });
  }

  const storedEmbeddings = result.rows.map((row) => ({
    id: row.id,
    angleType: row.angle_type,
    embedding:
      typeof row.embedding === 'string' ? JSON.parse(row.embedding) : row.embedding,
  }));

  const config = require('../config');
  const threshold = config.faceMatchThreshold;
  const live = prepareEmbedding(embedding);
  const match = evaluateFaceMatch(live, storedEmbeddings, threshold);

  console.log(
    `[verify] mode=${match.matchMode} sim=${match.similarity.toFixed(4)} ` +
      `threshold=${threshold} matched=${match.matched}`,
  );

  if (!match.matched) {
    await logFraud(req.user.id, sessionId ?? null, 'FACE_MISMATCH', {
      similarity: match.similarity,
      matchMode: match.matchMode,
      threshold,
    });
    return res.status(403).json({
      verified: false,
      similarity: match.similarity,
      minSimilarity: match.minSimilarity,
      maxSimilarity: match.maxSimilarity,
      threshold,
      matchMode: match.matchMode,
      preprocessSpec: FACE_PREPROCESS_SPEC.version,
      message:
        `Face not recognized (best ${(match.similarity * 100).toFixed(1)}%, ` +
        `need ${(threshold * 100).toFixed(0)}% or higher)`,
    });
  }

  await logAudit(req.user.id, 'FACE_VERIFIED', 'face_embeddings', match.embeddingId, {
    similarity: match.similarity,
    matchMode: match.matchMode,
    sessionId,
  });

  res.json({
    verified: true,
    similarity: match.similarity,
    minSimilarity: match.minSimilarity,
    maxSimilarity: match.maxSimilarity,
    threshold,
    matchMode: match.matchMode,
    preprocessSpec: FACE_PREPROCESS_SPEC.version,
    matchedEmbeddingId: match.embeddingId,
  });
}

async function verifyDevice(req, res) {
  const { deviceId, deviceFingerprint, deviceName } = req.body;
  const existing = await pool.query('SELECT * FROM devices WHERE user_id = $1', [
    req.user.id,
  ]);
  if (existing.rows.length === 0) {
    await pool.query(
      `INSERT INTO devices (user_id, device_id, device_fingerprint, device_name)
       VALUES ($1, $2, $3, $4)`,
      [req.user.id, deviceId, deviceFingerprint, deviceName],
    );
    return res.json({ bound: true, message: 'Device registered' });
  }
  const device = existing.rows[0];
  if (device.device_id !== deviceId || device.device_fingerprint !== deviceFingerprint) {
    await logFraud(req.user.id, null, 'DEVICE_MISMATCH', { deviceId });
    return res.status(403).json({ error: 'Device not authorized for this account' });
  }
  await pool.query('UPDATE devices SET last_seen_at = NOW() WHERE user_id = $1', [
    req.user.id,
  ]);
  res.json({ bound: true, verified: true });
}

module.exports = { registerEmbeddings, getMyEmbeddings, verifyEmbedding, verifyDevice };
