const pool = require('../database/pool');
const { logAudit, logFraud } = require('../services/auditService');

async function registerEmbeddings(req, res) {
  const { embeddings, deviceId } = req.body;
  if (!embeddings?.length) {
    return res.status(400).json({ error: 'At least one embedding required' });
  }
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query('DELETE FROM face_embeddings WHERE user_id = $1', [req.user.id]);
    for (const item of embeddings) {
      await client.query(
        `INSERT INTO face_embeddings (user_id, angle_type, embedding, device_id)
         VALUES ($1, $2, $3, $4)`,
        [req.user.id, item.angleType, JSON.stringify(item.embedding), deviceId],
      );
    }
    await client.query('COMMIT');
    await logAudit(req.user.id, 'FACE_REGISTERED', 'face_embeddings', req.user.id, {
      count: embeddings.length,
    });
    res.status(201).json({ message: 'Face embeddings registered', count: embeddings.length });
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}

async function getMyEmbeddings(req, res) {
  const result = await pool.query(
    `SELECT id, angle_type, registered_at FROM face_embeddings WHERE user_id = $1`,
    [req.user.id],
  );
  res.json({ registered: result.rows.length > 0, embeddings: result.rows });
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

module.exports = { registerEmbeddings, getMyEmbeddings, verifyDevice };
