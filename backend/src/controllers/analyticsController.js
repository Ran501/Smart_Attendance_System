const pool = require('../database/pool');

function normalizeModule(value) {
  return value == null
    ? ''
    : String(value).trim().toUpperCase().replace(/[^A-Z0-9]+/g, '-').replace(/^-+|-+$/g, '');
}

async function getTeacherAnalytics(req, res) {
  const { classId } = req.query;
  const moduleId = normalizeModule(req.query.moduleId || req.query.subjectId);
  const params = [req.user.id];
  let query = `
    SELECT s.id, s.id AS session_id, s.class_id, s.subject_id, s.started_at, s.ends_at, s.status,
           COALESCE(s.session_units, 1) AS session_units,
           COALESCE(s.session_units, 1) AS "sessionUnits",
           c.name AS class_name,
           sub.name as subject_name,
           sub.id AS module_id,
           COUNT(ar.id) FILTER (WHERE ar.status = 'PRESENT') as present,
           COUNT(ar.id) FILTER (WHERE ar.status = 'PRESENT') as present_count,
           COUNT(ar.id) FILTER (WHERE ar.status = 'REJECTED') as rejected,
           COUNT(ar.id) FILTER (WHERE ar.status = 'REJECTED') as rejected_count,
           COUNT(ar.id) FILTER (WHERE ar.status = 'ABSENT') as absent,
           COUNT(ar.id) FILTER (WHERE ar.status = 'MEDICAL_LEAVE') as medical_leave,
           COUNT(ar.id) FILTER (WHERE ar.status = 'OFFICIAL_LEAVE') as official_leave
    FROM attendance_sessions s
    JOIN subjects sub ON sub.id = s.subject_id
    JOIN classes c ON c.id = s.class_id
    LEFT JOIN attendance_records ar ON ar.session_id = s.id
    WHERE s.teacher_id = $1`;

  if (classId) {
    params.push(classId);
    query += ` AND s.class_id = $${params.length}`;
  }
  if (moduleId) {
    params.push(moduleId);
    query += ` AND (UPPER(s.subject_id) = $${params.length} OR UPPER(sub.code) = $${params.length})`;
  }

  query += ' GROUP BY s.id, sub.id, sub.name, c.name ORDER BY s.started_at DESC LIMIT 100';
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
  query += ' ORDER BY name';
  const result = await pool.query(query, params);
  res.json(result.rows);
}

async function getClasses(req, res) {
  const result = await pool.query('SELECT * FROM classes ORDER BY created_at DESC, id');
  res.json(result.rows);
}

async function getSubjects(req, res) {
  const { classId } = req.query;
  let query = `SELECT s.*, s.id AS subject_id, s.name AS subject_name,
                      c.name AS class_name, u.full_name as teacher_name,
                      (s.join_password_hash IS NOT NULL) AS has_join_password
               FROM subjects s
               JOIN classes c ON c.id = s.class_id
               LEFT JOIN users u ON u.id = s.teacher_id`;
  const params = [];
  if (classId) {
    query += ' WHERE s.class_id = $1';
    params.push(classId);
  }
  query += ' ORDER BY s.created_at DESC, s.name';
  const result = await pool.query(query, params);
  res.json(result.rows);
}

async function exportSessionReport(req, res) {
  const { sessionId } = req.params;
  const session = await pool.query(
    `SELECT s.*, c.name as class_name, sub.name as subject_name, u.full_name as teacher_name,
            COALESCE(s.session_units, 1) AS session_units
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

  const s = session.rows[0];
  if (req.user.role === 'teacher' && s.teacher_id !== req.user.id) {
    return res.status(403).json({ error: 'You can only export your own session reports' });
  }

  const records = await pool.query(
    `SELECT u.id AS user_id, u.full_name, u.student_id as student_code, u.email,
            ar.id AS record_id, COALESCE(ar.status, 'ABSENT') AS status,
            ar.match_confidence, ar.rejection_reason, ar.manual_note,
            ar.marked_at, ar.updated_at
     FROM class_enrollments ce
     JOIN users u ON u.id = ce.student_id
     LEFT JOIN attendance_records ar ON ar.session_id = $1 AND ar.student_id = u.id
     WHERE ce.class_id = $2 AND u.role = 'student'
     ORDER BY u.full_name`,
    [sessionId, s.class_id],
  );
  res.json({
    session: s,
    records: records.rows,
    exportedAt: new Date().toISOString(),
  });
}

async function exportModuleReport(req, res) {
  const moduleId = normalizeModule(req.params.moduleId || req.query.moduleId || req.query.subjectId);
  if (!moduleId) return res.status(400).json({ error: 'Module ID is required' });

  const params = [moduleId];
  let teacherFilter = '';
  if (req.user.role === 'teacher') {
    params.push(req.user.id);
    teacherFilter = `AND s.teacher_id = $${params.length}`;
  }

  const moduleInfo = await pool.query(
    `SELECT sub.id AS module_id, sub.name AS module_name, sub.code,
            c.id AS class_id, c.name AS class_name, c.department, c.semester,
            u.full_name AS teacher_name
     FROM subjects sub
     JOIN classes c ON c.id = sub.class_id
     LEFT JOIN users u ON u.id = sub.teacher_id
     WHERE UPPER(sub.id) = $1 OR UPPER(sub.code) = $1
     LIMIT 1`,
    [moduleId],
  );

  const rows = await pool.query(
    `WITH module_sessions AS (
       SELECT s.*, COALESCE(s.session_units, 1) AS units
       FROM attendance_sessions s
       JOIN subjects sub ON sub.id = s.subject_id
       WHERE (UPPER(s.subject_id) = $1 OR UPPER(sub.code) = $1) ${teacherFilter}
     ), students AS (
       SELECT DISTINCT u.id, u.full_name, u.student_id, u.email
       FROM module_sessions ms
       JOIN class_enrollments ce ON ce.class_id = ms.class_id
       JOIN users u ON u.id = ce.student_id
       WHERE u.role = 'student'
     )
     SELECT st.id AS student_uuid, st.full_name, st.student_id AS student_code, st.email,
            COALESCE(SUM(ms.units), 0)::int AS total_units,
            COALESCE(SUM(ms.units) FILTER (WHERE ar.status = 'PRESENT'), 0)::int AS present_units,
            COALESCE(SUM(ms.units) FILTER (WHERE COALESCE(ar.status, 'ABSENT') = 'ABSENT'), 0)::int AS absent_units,
            COALESCE(SUM(ms.units) FILTER (WHERE ar.status = 'MEDICAL_LEAVE'), 0)::int AS medical_leave_units,
            COALESCE(SUM(ms.units) FILTER (WHERE ar.status = 'OFFICIAL_LEAVE'), 0)::int AS official_leave_units,
            COALESCE(SUM(ms.units) FILTER (WHERE ar.status = 'REJECTED'), 0)::int AS rejected_units
     FROM students st
     CROSS JOIN module_sessions ms
     LEFT JOIN attendance_records ar ON ar.session_id = ms.id AND ar.student_id = st.id
     GROUP BY st.id, st.full_name, st.student_id, st.email
     ORDER BY st.full_name`,
    params,
  );

  res.json({
    module: moduleInfo.rows[0] || { module_id: moduleId },
    students: rows.rows,
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
  exportModuleReport,
};
