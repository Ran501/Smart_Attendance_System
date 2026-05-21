const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');
require('dotenv').config();

async function run() {
  const pool = new Pool({ connectionString: process.env.DATABASE_URL });
  const file = process.argv[2] || '001_session_host_location.sql';
  const sql = fs.readFileSync(
    path.join(__dirname, '../../database/migrations', file),
    'utf8',
  );
  try {
    await pool.query(sql);
    console.log(`Migration ${file} applied.`);
  } catch (err) {
    console.error('Migration failed:', err.message);
    process.exit(1);
  } finally {
    await pool.end();
  }
}

run();
