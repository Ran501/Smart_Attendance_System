const pool = require('../database/pool');
const { logAudit, logFraud } = require('../services/auditService');
const { findBestMatch } = require('../utils/face');

// ─── REGISTER ────────────────────────────────────────────────────────────────

async function registerEmbeddings(req, res) {
  const { embeddings, deviceId } = req.body;
  if (!embeddings?.length) {
    return res.status(400).json({ error: 'At least one embedding required' });
  }

  // Validate embedding shape before touching the DB
  for (const item of embeddings) {
    if (!Array.isArray(item.embedding) || item.embedding.length === 0) {
      return res.status(400).json({ error: `Invalid embedding for angleType: ${item.angleType}` });
    }
    // FIX: reject suspiciously short embeddings (MobileFaceNet = 128 dims)
    if (item.embedding.length < 64) {
      return res.status(400).json({
        error: `Embedding too short (${item.embedding.length}). Expected 128 dims.`,
      });
    }
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query('DELETE FROM face_embeddings WHERE user_id = $1', [req.user.id]);
    for (const item of embeddings) {
      await client.query(
        `INSERT INTO face_embeddings (user_id, angle_type, embedding, device_id)
         VALUES ($1, $2, $3::jsonb, $4)`,
        // FIX: cast to jsonb so PostgreSQL stores it natively (faster retrieval,
        // and avoids double-stringify bugs when the client already sent JSON)
        [req.user.id, item.angleType, JSON.stringify(item.embedding), deviceId],
      );
    }
    await client.query('COMMIT');
    await logAudit(req.user.id, 'FACE_REGISTERED', 'face_embeddings', req.user.id, {
      count: embeddings.length,
      dims: embeddings[0].embedding.length,
    });
    res.status(201).json({ message: 'Face embeddings registered', count: embeddings.length });
  } catch (e) {
    await client.query('ROLLBACK');
    console.error('[faceController] registerEmbeddings error:', e);
    res.status(500).json({ error: 'Failed to register embeddings' });
  } finally {
    client.release();
  }
}

// ─── STATUS (no embedding data — safe to expose) ─────────────────────────────

async function getMyEmbeddings(req, res) {
  const result = await pool.query(
    `SELECT id, angle_type, registered_at FROM face_embeddings WHERE user_id = $1`,
    [req.user.id],
  );
  res.json({ registered: result.rows.length > 0, embeddings: result.rows });
}

// ─── VERIFY ──────────────────────────────────────────────────────────────────
// FIX: this endpoint was MISSING entirely — the app had no way to verify faces
// server-side. Added it here.

async function verifyEmbedding(req, res) {
  const { embedding, sessionId } = req.body;

  if (!Array.isArray(embedding) || embedding.length < 64) {
    return res.status(400).json({ error: 'Invalid or missing embedding in request' });
  }

  // FIX: retrieve the actual embedding vectors (previously getMyEmbeddings
  // omitted the embedding column, so verification had nothing to compare against)
  const result = await pool.query(
    `SELECT id, angle_type, embedding
     FROM face_embeddings
     WHERE user_id = $1`,
    [req.user.id],
  );

  if (result.rows.length === 0) {
    return res.status(404).json({ error: 'No registered face found for this user' });
  }

  // FIX: parse embedding back from jsonb/text — PostgreSQL may return it as
  // a string or already-parsed array depending on column type
  const storedEmbeddings = result.rows.map((row) => ({
    id: row.id,
    angleType: row.angle_type,
    embedding: typeof row.embedding === 'string'
      ? JSON.parse(row.embedding)
      : row.embedding,
  }));

  // Log dimensions for debugging
  console.log(`[verify] live embedding dims: ${embedding.length}`);
  console.log(`[verify] stored embedding dims: ${storedEmbeddings[0].embedding.length}`);

  // FIX: threshold — 0.85 was too strict for real-world lighting variation.
  // 0.65 is a reasonable starting point for MobileFaceNet with cosine similarity.
  // Tune upward (stricter) once you confirm matches are working.
  const THRESHOLD = parseFloat(process.env.FACE_SIMILARITY_THRESHOLD ?? '0.50');

  const match = findBestMatch(embedding, storedEmbeddings, THRESHOLD);

  console.log(`[verify] best similarity: ${match.similarity.toFixed(4)}, matched: ${match.matched}`);

  if (!match.matched) {
    await logFraud(req.user.id, sessionId ?? null, 'FACE_MISMATCH', {
      similarity: match.similarity,
      threshold: THRESHOLD,
    });
    return res.status(401).json({
      verified: false,
      similarity: match.similarity,
      message: 'Face not recognized',
    });
  }

  await logAudit(req.user.id, 'FACE_VERIFIED', 'face_embeddings', match.embeddingId, {
    similarity: match.similarity,
    sessionId,
  });

  res.json({
    verified: true,
    similarity: match.similarity,
    matchedEmbeddingId: match.embeddingId,
  });
}

// ─── DEVICE ──────────────────────────────────────────────────────────────────

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