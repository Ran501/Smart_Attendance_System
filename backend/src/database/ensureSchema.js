const pool = require('./pool');

async function ensureRuntimeSchema() {
  const statements = [
    `DO $$
     BEGIN
       IF NOT EXISTS (
         SELECT 1 FROM pg_enum
         WHERE enumlabel = 'MEDICAL_LEAVE'
           AND enumtypid = 'attendance_status'::regtype
       ) THEN
         ALTER TYPE attendance_status ADD VALUE 'MEDICAL_LEAVE';
       END IF;
     END $$;`,
    `DO $$
     BEGIN
       IF NOT EXISTS (
         SELECT 1 FROM pg_enum
         WHERE enumlabel = 'OFFICIAL_LEAVE'
           AND enumtypid = 'attendance_status'::regtype
       ) THEN
         ALTER TYPE attendance_status ADD VALUE 'OFFICIAL_LEAVE';
       END IF;
     END $$;`,
    `ALTER TABLE subjects
       ADD COLUMN IF NOT EXISTS join_password_hash VARCHAR(255);`,
    `ALTER TABLE attendance_sessions
       ADD COLUMN IF NOT EXISTS host_latitude DOUBLE PRECISION,
       ADD COLUMN IF NOT EXISTS host_longitude DOUBLE PRECISION,
       ADD COLUMN IF NOT EXISTS radius_meters INTEGER DEFAULT 100,
       ADD COLUMN IF NOT EXISTS host_accuracy DOUBLE PRECISION,
       ADD COLUMN IF NOT EXISTS session_units INTEGER DEFAULT 1;`,
    `UPDATE attendance_sessions
       SET session_units = 1
       WHERE session_units IS NULL;`,
    `DO $$
     BEGIN
       IF NOT EXISTS (
         SELECT 1 FROM pg_constraint
         WHERE conname = 'attendance_sessions_session_units_check'
       ) THEN
         ALTER TABLE attendance_sessions
           ADD CONSTRAINT attendance_sessions_session_units_check
           CHECK (session_units >= 1 AND session_units <= 3);
       END IF;
     END $$;`,
    `ALTER TABLE attendance_records
       ADD COLUMN IF NOT EXISTS manual_note TEXT,
       ADD COLUMN IF NOT EXISTS updated_by UUID REFERENCES users(id),
       ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ,
       ADD COLUMN IF NOT EXISTS ble_verified BOOLEAN,
       ADD COLUMN IF NOT EXISTS ble_rssi INTEGER;`,
    `ALTER TABLE attendance_sessions DROP COLUMN IF EXISTS qr_payload;`,
    `CREATE INDEX IF NOT EXISTS idx_sessions_subject ON attendance_sessions(subject_id);`,
    `CREATE INDEX IF NOT EXISTS idx_subjects_teacher ON subjects(teacher_id);`,

    // FCM device tokens — one row per user+device
    `CREATE TABLE IF NOT EXISTS device_tokens (
       id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
       user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
       token       TEXT NOT NULL,
       updated_at  TIMESTAMPTZ DEFAULT NOW(),
       UNIQUE(user_id, token)
     );`,
    `CREATE INDEX IF NOT EXISTS idx_device_tokens_user ON device_tokens(user_id);`,

    // In-app notification history
    `CREATE TABLE IF NOT EXISTS notifications (
       id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
       user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
       type        TEXT NOT NULL,
       title       TEXT NOT NULL,
       body        TEXT NOT NULL,
       data        JSONB DEFAULT '{}',
       is_read     BOOLEAN DEFAULT FALSE,
       created_at  TIMESTAMPTZ DEFAULT NOW()
     );`,
    `CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id, created_at DESC);`,
  ];

  const client = await pool.connect();
  try {
    for (const sql of statements) {
      await client.query(sql);
    }
  } finally {
    client.release();
  }
}

module.exports = { ensureRuntimeSchema };
