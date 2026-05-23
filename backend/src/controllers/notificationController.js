const pool = require('../database/pool');

async function registerToken(req, res) {
  const { token } = req.body;
  if (!token || typeof token !== 'string') {
    return res.status(400).json({ error: 'token is required' });
  }
  await pool.query(
    `INSERT INTO device_tokens (user_id, token, updated_at)
     VALUES ($1, $2, NOW())
     ON CONFLICT (user_id, token) DO UPDATE SET updated_at = NOW()`,
    [req.user.id, token.trim()],
  );
  console.log(`[FCM] Registered device token for user ${req.user.id}`);
  return res.json({ success: true });
}

async function listNotifications(req, res) {
  const result = await pool.query(
    `SELECT id, type, title, body, data, is_read, created_at
     FROM notifications
     WHERE user_id = $1
     ORDER BY created_at DESC
     LIMIT 50`,
    [req.user.id],
  );
  res.json(result.rows);
}

async function markRead(req, res) {
  const { id } = req.params;
  if (id === 'all') {
    await pool.query(
      'UPDATE notifications SET is_read = TRUE WHERE user_id = $1',
      [req.user.id],
    );
  } else {
    await pool.query(
      'UPDATE notifications SET is_read = TRUE WHERE id = $1 AND user_id = $2',
      [id, req.user.id],
    );
  }
  res.json({ success: true });
}

async function unreadCount(req, res) {
  const result = await pool.query(
    'SELECT COUNT(*)::int AS count FROM notifications WHERE user_id = $1 AND is_read = FALSE',
    [req.user.id],
  );
  res.json({ count: result.rows[0]?.count ?? 0 });
}

module.exports = { registerToken, listNotifications, markRead, unreadCount };
