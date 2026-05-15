const pool = require('../database/pool');

async function getTeacherAnalytics(req, res) {
  const { classId } = req.query;
  let query = `
    SELECT s.id, s.class_id, s.started_at, s.ends_at, s.status,
           sub.name as subject_name,
           COUNT(ar.id) FILTER (WHERE ar.status = 'PRESENT') as present,
           COUNT(ar.id) FILTER (WHERE ar.status = 'REJECTED') as rejected
    FROM attendance_sessions s
    JOIN subjects sub ON sub.id = s.subject_id
    LEFT JOIN attendance_records ar ON ar.session_id = s.id
    WHERE s.teacher_id = $1`;
  const params = [req.user.id];
  if (classId) {
    query += ' AND s.class_id = $2';
    params.push(classId);
  }
  query += ' GROUP BY s.id, sub.name ORDER BY s.started_at DESC LIMIT 50';
  const result = await pool.query(query, params);
  res.json(result.rows);
}

async function getAdminFraudLogs(req, res) {
  const result = await pool.query(
    `SELECT f.*, u.full_name, u.email
     FROM fraud_logs f
     LEFT JOIN users u ON u.id = f.user_id
     ORDER BY f.created_at DESC LIMIT 200`,
  );
  res.json(result.rows);
}

async function getAdminUsers(req, res) {
  const result = await pool.query(
    `SELECT id, email, full_name, role, student_id, is_active, created_at
     FROM users ORDER BY created_at DESC`,
  );
  res.json(result.rows);
}

async function getClassrooms(req, res) {
  const { classId } = req.query;
  let query = 'SELECT * FROM classrooms';
  const params = [];
  if (classId) {
    query += ' WHERE class_id = $1';
    params.push(classId);
  }
  const result = await pool.query(query, params);
  res.json(result.rows);
}

async function getClasses(req, res) {
  const result = await pool.query('SELECT * FROM classes ORDER BY id');
  res.json(result.rows);
}

async function getSubjects(req, res) {
  const { classId } = req.query;
  let query = `SELECT s.*, u.full_name as teacher_name FROM subjects s
                 LEFT JOIN users u ON u.id = s.teacher_id`;
  const params = [];
  if (classId) {
    query += ' WHERE s.class_id = $1';
    params.push(classId);
  }
  const result = await pool.query(query, params);
  res.json(result.rows);
}

async function exportSessionReport(req, res) {
  const { sessionId } = req.params;
  const session = await pool.query(
    `SELECT s.*, c.name as class_name, sub.name as subject_name, u.full_name as teacher_name
     FROM attendance_sessions s
     JOIN classes c ON c.id = s.class_id
     JOIN subjects sub ON sub.id = s.subject_id
     JOIN users u ON u.id = s.teacher_id
     WHERE s.id = $1`,
    [sessionId],
  );
  if (!session.rows.length) {
    return res.status(404).json({ error: 'Session not found' });
  }
  const records = await pool.query(
    `SELECT ar.*, u.full_name, u.student_id as student_code, u.email
     FROM attendance_records ar
     JOIN users u ON u.id = ar.student_id
     WHERE ar.session_id = $1 ORDER BY u.full_name`,
    [sessionId],
  );
  res.json({
    session: session.rows[0],
    records: records.rows,
    exportedAt: new Date().toISOString(),
  });
}

module.exports = {
  getTeacherAnalytics,
  getAdminFraudLogs,
  getAdminUsers,
  getClassrooms,
  getClasses,
  getSubjects,
  exportSessionReport,
};
