const pool = require('../database/pool');

async function generateSessionId(classId, subjectCode) {
  const prefix = `ATT-${(subjectCode || 'GEN').replace(/[^A-Z0-9]/gi, '').toUpperCase().slice(0, 8)}`;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const seq = await client.query(
      `INSERT INTO session_sequence (prefix, last_number)
       VALUES ($1, 1)
       ON CONFLICT (prefix) DO UPDATE SET last_number = session_sequence.last_number + 1
       RETURNING last_number`,
      [prefix],
    );
    const num = String(seq.rows[0].last_number).padStart(5, '0');
    await client.query('COMMIT');
    return `${prefix}-${num}`;
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

module.exports = { generateSessionId, generateSessionToken };
