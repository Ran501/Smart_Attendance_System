const pool = require('../database/pool');

async function logAudit(userId, action, resourceType, resourceId, metadata = {}) {
  await pool.query(
    `INSERT INTO audit_logs (user_id, action, resource_type, resource_id, metadata)
     VALUES ($1, $2, $3, $4, $5)`,
    [userId, action, resourceType, resourceId, JSON.stringify(metadata)],
  );
}

async function logFraud(userId, sessionId, attemptType, details = {}) {
  await pool.query(
    `INSERT INTO fraud_logs (user_id, session_id, attempt_type, details)
     VALUES ($1, $2, $3, $4)`,
    [userId, sessionId, attemptType, JSON.stringify(details)],
  );
}

module.exports = { logAudit, logFraud };
