const bcrypt = require('bcryptjs');
const pool = require('../database/pool');
const { logAudit } = require('../services/auditService');

function clean(value) {
  return value == null ? '' : String(value).trim();
}

function normalizeCode(value, fallback = 'MOD') {
  const raw = clean(value || fallback).toUpperCase();
  return raw.replace(/[^A-Z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 50) || fallback;
}

function subjectCodeFrom(moduleId) {
  return normalizeCode(moduleId, 'MOD').replace(/-/g, '').slice(0, 20) || 'MOD';
}

function modulePayload(row) {
  return {
    id: row.subject_id,
    module_id: row.subject_id,
    moduleId: row.subject_id,
    subject_id: row.subject_id,
    subjectId: row.subject_id,
    code: row.code,
    name: row.subject_name,
    module_name: row.subject_name,
    moduleName: row.subject_name,
    subject_name: row.subject_name,
    subjectName: row.subject_name,
    class_id: row.class_id,
    classId: row.class_id,
    class_name: row.class_name,
    className: row.class_name,
    department: row.department,
    semester: row.semester,
    teacher_id: row.teacher_id,
    teacher_name: row.teacher_name,
    has_join_password: !!row.has_join_password,
    created_at: row.created_at,
  };
}

async function listTeacherModules(req, res) {
  const params = [];
  let where = '';
  if (req.user.role !== 'admin') {
    params.push(req.user.id);
    where = 'WHERE s.teacher_id = $1';
  }

  const result = await pool.query(
    `SELECT s.id AS subject_id, s.name AS subject_name, s.code, s.class_id,
            s.teacher_id, s.created_at, c.name AS class_name, c.department, c.semester,
            u.full_name AS teacher_name, (s.join_password_hash IS NOT NULL) AS has_join_password
     FROM subjects s
     JOIN classes c ON c.id = s.class_id
     LEFT JOIN users u ON u.id = s.teacher_id
     ${where}
     ORDER BY s.created_at DESC, s.name ASC`,
    params,
  );

  res.json({ modules: result.rows.map(modulePayload) });
}

async function createModule(req, res) {
  const moduleId = normalizeCode(
    req.body.moduleId || req.body.subjectId || req.body.id || req.body.code,
    'MODULE',
  );
  const moduleName = clean(req.body.moduleName || req.body.subjectName || req.body.name);
  const password = clean(req.body.joinPassword || req.body.password);
  const classNameInput = clean(req.body.className || req.body.programme || req.body.class_name);
  const department = clean(req.body.department || '');
  const section = clean(req.body.section || req.body.semester || '');

  if (!moduleName) {
    return res.status(400).json({ error: 'Module name is required' });
  }
  if (!password || password.length < 3) {
    return res.status(400).json({ error: 'Join password must be at least 3 characters' });
  }

  // The Flutter UI sends classId = moduleId as a compatibility fallback.
  // If a class/section name is provided, use that as the real class id.
  const requestedClassId = clean(req.body.classId || req.body.class_id);
  const classId = normalizeCode(
    classNameInput || (requestedClassId && requestedClassId !== moduleId ? requestedClassId : '') || `${moduleId}-CLASS`,
    'CLASS',
  );
  const className = classNameInput || section || classId;
  const joinPasswordHash = await bcrypt.hash(password, 12);

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    await client.query(
      `INSERT INTO classes (id, name, department, semester)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (id) DO UPDATE SET
         name = EXCLUDED.name,
         department = COALESCE(NULLIF(EXCLUDED.department, ''), classes.department),
         semester = COALESCE(NULLIF(EXCLUDED.semester, ''), classes.semester)`,
      [classId, className, department || null, section || null],
    );

    const subject = await client.query(
      `INSERT INTO subjects (id, name, code, class_id, teacher_id, join_password_hash)
       VALUES ($1, $2, $3, $4, $5, $6)
       ON CONFLICT (id) DO UPDATE SET
         name = EXCLUDED.name,
         code = EXCLUDED.code,
         class_id = EXCLUDED.class_id,
         teacher_id = EXCLUDED.teacher_id,
         join_password_hash = EXCLUDED.join_password_hash
       RETURNING id AS subject_id, name AS subject_name, code, class_id, teacher_id, created_at,
                 (join_password_hash IS NOT NULL) AS has_join_password`,
      [moduleId, moduleName, subjectCodeFrom(moduleId), classId, req.user.id, joinPasswordHash],
    );

    // Create a default classroom so the teacher can immediately start a session.
    await client.query(
      `INSERT INTO classrooms (name, class_id, latitude, longitude, radius_meters, allowed_wifi_ssid)
       VALUES ($1, $2, $3, $4, $5, $6)
       ON CONFLICT DO NOTHING`,
      ['Default Classroom', classId, 27.7172, 85.3240, 100, 'Campus-WiFi'],
    );

    await client.query('COMMIT');

    await logAudit(req.user.id, 'MODULE_CREATED', 'subject', moduleId, { classId });

    const row = subject.rows[0];
    const payload = modulePayload({
      ...row,
      class_name: className,
      department,
      semester: section,
      teacher_name: req.user.email,
    });

    if (req.io) req.io.emit('module:created', payload);

    res.status(201).json({ message: 'Module created', module: payload, ...payload });
  } catch (err) {
    await client.query('ROLLBACK');
    if (err.code === '23505') {
      return res.status(409).json({ error: 'Module ID already exists' });
    }
    throw err;
  } finally {
    client.release();
  }
}

async function joinModule(req, res) {
  if (req.user.role !== 'student') {
    return res.status(403).json({ error: 'Only students can join modules' });
  }

  const moduleId = normalizeCode(req.body.moduleId || req.body.subjectId || req.body.classId || req.body.id, '');
  const password = clean(req.body.joinPassword || req.body.password);
  if (!moduleId || !password) {
    return res.status(400).json({ error: 'Module ID and password are required' });
  }

  const result = await pool.query(
    `SELECT s.id AS subject_id, s.name AS subject_name, s.code, s.class_id,
            s.teacher_id, s.join_password_hash, s.created_at,
            c.name AS class_name, c.department, c.semester,
            u.full_name AS teacher_name,
            (s.join_password_hash IS NOT NULL) AS has_join_password
     FROM subjects s
     JOIN classes c ON c.id = s.class_id
     LEFT JOIN users u ON u.id = s.teacher_id
     WHERE UPPER(s.id) = $1 OR UPPER(s.code) = $1
     LIMIT 1`,
    [moduleId],
  );

  if (!result.rows.length) {
    return res.status(404).json({ error: 'Module not found' });
  }

  const row = result.rows[0];
  if (row.join_password_hash) {
    const ok = await bcrypt.compare(password, row.join_password_hash);
    if (!ok) return res.status(403).json({ error: 'Incorrect module password' });
  }

  await pool.query(
    `INSERT INTO class_enrollments (student_id, class_id)
     VALUES ($1, $2)
     ON CONFLICT DO NOTHING`,
    [req.user.id, row.class_id],
  );

  await logAudit(req.user.id, 'MODULE_JOINED', 'subject', row.subject_id, {
    classId: row.class_id,
  });

  const payload = modulePayload(row);
  if (req.io) {
    req.io.to(`class:${row.class_id}`).emit('module:joined', {
      moduleId: row.subject_id,
      studentId: req.user.id,
    });
  }

  res.json({ message: 'Module joined successfully', module: payload, ...payload });
}

async function getModuleSessions(req, res) {
  const moduleId = normalizeCode(req.params.moduleId || req.params.subjectId || req.query.moduleId || req.query.subjectId, '');
  if (!moduleId) return res.status(400).json({ error: 'Module ID is required' });

  const params = [moduleId];
  let teacherFilter = '';
  if (req.user.role === 'teacher') {
    params.push(req.user.id);
    teacherFilter = `AND s.teacher_id = $${params.length}`;
  }

  const result = await pool.query(
    `SELECT s.id, s.id AS session_id, s.class_id, s.subject_id, s.status,
            s.started_at, s.ends_at, s.closed_at, s.duration_minutes,
            COALESCE(s.session_units, 1) AS session_units,
            COALESCE(s.session_units, 1) AS "sessionUnits",
            c.name AS class_name, sub.name AS subject_name,
            COUNT(ar.id) FILTER (WHERE ar.status = 'PRESENT') AS present,
            COUNT(ar.id) FILTER (WHERE ar.status = 'PRESENT') AS present_count,
            COUNT(ar.id) FILTER (WHERE ar.status = 'REJECTED') AS rejected,
            COUNT(ar.id) FILTER (WHERE ar.status = 'REJECTED') AS rejected_count,
            COUNT(ar.id) FILTER (WHERE ar.status = 'ABSENT') AS absent,
            COUNT(ar.id) FILTER (WHERE ar.status = 'MEDICAL_LEAVE') AS medical_leave,
            COUNT(ar.id) FILTER (WHERE ar.status = 'OFFICIAL_LEAVE') AS official_leave
     FROM attendance_sessions s
     JOIN subjects sub ON sub.id = s.subject_id
     JOIN classes c ON c.id = s.class_id
     LEFT JOIN attendance_records ar ON ar.session_id = s.id
     WHERE (UPPER(s.subject_id) = $1 OR UPPER(sub.code) = $1) ${teacherFilter}
     GROUP BY s.id, c.name, sub.name
     ORDER BY s.started_at DESC`,
    params,
  );

  res.json({ sessions: result.rows });
}

async function getModuleSummary(req, res) {
  const moduleId = normalizeCode(req.params.moduleId || req.query.moduleId || req.query.subjectId, '');
  if (!moduleId) return res.status(400).json({ error: 'Module ID is required' });

  const params = [moduleId];
  let teacherFilter = '';
  if (req.user.role === 'teacher') {
    params.push(req.user.id);
    teacherFilter = `AND s.teacher_id = $${params.length}`;
  }

  const result = await pool.query(
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
     SELECT st.id AS student_id, st.full_name, st.student_id AS student_code, st.email,
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

  const rows = result.rows.map((r) => {
    const total = Number(r.total_units) || 0;
    const present = Number(r.present_units) || 0;
    const absent = Number(r.absent_units) || 0;
    const medical = Number(r.medical_leave_units) || 0;
    const official = Number(r.official_leave_units) || 0;
    const presentPercentage = total ? (present / total) * 100 : 0;
    const absentRulePercentage = total ? ((total - absent) / total) * 100 : 0;
    const leaveRulePercentage = total ? ((total - absent - medical - official) / total) * 100 : 0;
    return {
      ...r,
      present_percentage: presentPercentage,
      absent_rule_percentage: absentRulePercentage,
      leave_rule_percentage: leaveRulePercentage,
      status: absentRulePercentage >= 90 && leaveRulePercentage >= 80 ? 'SAFE' : 'AT_RISK',
    };
  });

  res.json({ moduleId, students: rows, generatedAt: new Date().toISOString() });
}

module.exports = {
  listTeacherModules,
  createModule,
  joinModule,
  getModuleSessions,
  getModuleSummary,
};
