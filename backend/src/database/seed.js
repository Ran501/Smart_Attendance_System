const bcrypt = require('bcryptjs');
const { Pool } = require('pg');
require('dotenv').config();

async function seed() {
  const pool = new Pool({ connectionString: process.env.DATABASE_URL });
  const passwordHash = await bcrypt.hash('password123', 12);

  try {
    await pool.query(`
      INSERT INTO classes (id, name, department, semester)
      VALUES ('CST-S5-A', 'Computer Science S5 A', 'CSIT', 'S5')
      ON CONFLICT (id) DO NOTHING
    `);

    const admin = await pool.query(
      `INSERT INTO users (email, password_hash, full_name, role)
       VALUES ('admin@college.edu', $1, 'System Admin', 'admin')
       ON CONFLICT (email) DO NOTHING RETURNING id`,
      [passwordHash],
    );

    const teacher = await pool.query(
      `INSERT INTO users (email, password_hash, full_name, role)
       VALUES ('teacher@college.edu', $1, 'Dr. Jane Smith', 'teacher')
       ON CONFLICT (email) DO NOTHING RETURNING id`,
      [passwordHash],
    );

    const student = await pool.query(
      `INSERT INTO users (email, password_hash, full_name, role, student_id)
       VALUES ('student@college.edu', $1, 'John Doe', 'student', 'STU-2024-001')
       ON CONFLICT (email) DO NOTHING RETURNING id`,
      [passwordHash],
    );

    const teacherId = teacher.rows[0]?.id;
    if (teacherId) {
      await pool.query(
        `INSERT INTO subjects (id, name, code, class_id, teacher_id)
         VALUES ('SUB-CS101', 'Data Structures', 'CS101', 'CST-S5-A', $1)
         ON CONFLICT (id) DO NOTHING`,
        [teacherId],
      );
    }

    const studentId = student.rows[0]?.id;
    if (studentId) {
      await pool.query(
        `INSERT INTO class_enrollments (student_id, class_id)
         VALUES ($1, 'CST-S5-A') ON CONFLICT DO NOTHING`,
        [studentId],
      );
    }

    await pool.query(
      `INSERT INTO classrooms (name, class_id, latitude, longitude, radius_meters, allowed_wifi_ssid)
       VALUES ('Lab 301', 'CST-S5-A', 27.7172, 85.3240, 30, 'Campus-WiFi')
       ON CONFLICT DO NOTHING`,
    );

    console.log('Seed completed. Demo accounts (password: password123):');
    console.log('  admin@college.edu, teacher@college.edu, student@college.edu');
  } catch (err) {
    console.error('Seed failed:', err.message);
    process.exit(1);
  } finally {
    await pool.end();
  }
}

seed();
