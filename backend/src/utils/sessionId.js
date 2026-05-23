const pool = require('../database/pool');

function buildSessionIdPrefix(subjectCode) {
  const code = (subjectCode || 'GEN').replace(/[^A-Z0-9]/gi, '').toUpperCase().slice(0, 8);
  return `ATT-${code}`;
}

/**
 * Next session id for a module: ATT-{SUBJECT_CODE}-00001, 00002, …
 * Numbering is per subject_id from rows still in attendance_sessions only
 * (the old session_sequence counter is no longer used).
 */
async function generateSessionId(subjectId, subjectCode) {
  const prefix = buildSessionIdPrefix(subjectCode);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1::text))', [subjectId]);

    const maxRes = await client.query(
      `SELECT COALESCE(MAX(CAST(RIGHT(id, 5) AS INTEGER)), 0) + 1 AS next_num
       FROM attendance_sessions
       WHERE subject_id = $1
         AND id LIKE $2 || '-%'
         AND RIGHT(id, 5) ~ '^[0-9]{5}$'`,
      [subjectId, prefix],
    );
    const nextNum = maxRes.rows[0].next_num;
    const sessionId = `${prefix}-${String(nextNum).padStart(5, '0')}`;

    await client.query('COMMIT');
    return sessionId;
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}

function generateSessionToken() {
  return require('crypto').randomBytes(32).toString('hex');
}

module.exports = { generateSessionId, generateSessionToken, buildSessionIdPrefix };
