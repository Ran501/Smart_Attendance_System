const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const pool = require('../database/pool');
const config = require('../config');
const { logAudit } = require('../services/auditService');

async function login(req, res) {
  const { email, password } = req.body;
  const result = await pool.query(
    `SELECT id, email, password_hash, full_name, role, student_id, is_active
     FROM users WHERE email = $1`,
    [email.toLowerCase()],
  );
  const user = result.rows[0];
  if (!user || !user.is_active) {
    return res.status(401).json({ error: 'Invalid credentials' });
  }
  const valid = await bcrypt.compare(password, user.password_hash);
  if (!valid) {
    return res.status(401).json({ error: 'Invalid credentials' });
  }
  const token = jwt.sign(
    { id: user.id, email: user.email, role: user.role, studentId: user.student_id },
    config.jwt.secret,
    { expiresIn: config.jwt.expiresIn },
  );
  await logAudit(user.id, 'LOGIN', 'user', user.id);
  res.json({
    token,
    user: {
      id: user.id,
      email: user.email,
      fullName: user.full_name,
      role: user.role,
      studentId: user.student_id,
    },
  });
}

async function register(req, res) {
  const { email, password, fullName, role, studentId } = req.body;
  const existing = await pool.query('SELECT id FROM users WHERE email = $1', [
    email.toLowerCase(),
  ]);
  if (existing.rows.length) {
    return res.status(409).json({ error: 'Email already registered' });
  }
  const passwordHash = await bcrypt.hash(password, 12);
  const result = await pool.query(
    `INSERT INTO users (email, password_hash, full_name, role, student_id)
     VALUES ($1, $2, $3, $4, $5)
     RETURNING id, email, full_name, role, student_id`,
    [email.toLowerCase(), passwordHash, fullName, role, studentId || null],
  );
  const user = result.rows[0];
  const token = jwt.sign(
    { id: user.id, email: user.email, role: user.role, studentId: user.student_id },
    config.jwt.secret,
    { expiresIn: config.jwt.expiresIn },
  );
  res.status(201).json({
    token,
    user: {
      id: user.id,
      email: user.email,
      fullName: user.full_name,
      role: user.role,
      studentId: user.student_id,
    },
  });
}

async function me(req, res) {
  const result = await pool.query(
    `SELECT id, email, full_name, role, student_id, created_at
     FROM users WHERE id = $1`,
    [req.user.id],
  );
  if (!result.rows.length) {
    return res.status(404).json({ error: 'User not found' });
  }
  const u = result.rows[0];
  res.json({
    id: u.id,
    email: u.email,
    fullName: u.full_name,
    role: u.role,
    studentId: u.student_id,
  });
}

module.exports = { login, register, me };
