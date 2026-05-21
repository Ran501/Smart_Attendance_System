-- Smart Attendance Management System - PostgreSQL Schema

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TYPE user_role AS ENUM ('student', 'teacher', 'admin');
CREATE TYPE attendance_status AS ENUM ('PRESENT', 'LATE', 'ABSENT', 'REJECTED', 'MEDICAL_LEAVE', 'OFFICIAL_LEAVE');
CREATE TYPE session_status AS ENUM ('active', 'expired', 'closed');

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(255) NOT NULL,
    role user_role NOT NULL,
    student_id VARCHAR(50) UNIQUE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE classes (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    department VARCHAR(100),
    semester VARCHAR(20),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE subjects (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    code VARCHAR(20) NOT NULL,
    class_id VARCHAR(50) REFERENCES classes(id) ON DELETE CASCADE,
    teacher_id UUID REFERENCES users(id),
    join_password_hash VARCHAR(255),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE class_enrollments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    student_id UUID REFERENCES users(id) ON DELETE CASCADE,
    class_id VARCHAR(50) REFERENCES classes(id) ON DELETE CASCADE,
    enrolled_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(student_id, class_id)
);

CREATE TABLE classrooms (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    class_id VARCHAR(50) REFERENCES classes(id),
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    radius_meters INTEGER DEFAULT 30,
    allowed_wifi_ssid VARCHAR(255),
    allowed_wifi_bssid VARCHAR(50),
    allowed_subnet VARCHAR(50),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE devices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    device_id VARCHAR(255) NOT NULL,
    device_fingerprint VARCHAR(512) NOT NULL,
    device_name VARCHAR(255),
    registered_at TIMESTAMPTZ DEFAULT NOW(),
    last_seen_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE face_embeddings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    angle_type VARCHAR(50) NOT NULL,
    embedding JSONB NOT NULL,
    device_id VARCHAR(255),
    registered_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_face_embeddings_user ON face_embeddings(user_id);

CREATE TABLE attendance_sessions (
    id VARCHAR(50) PRIMARY KEY,
    class_id VARCHAR(50) REFERENCES classes(id),
    subject_id VARCHAR(50) REFERENCES subjects(id),
    teacher_id UUID REFERENCES users(id),
    classroom_id UUID REFERENCES classrooms(id),
    session_token VARCHAR(255) UNIQUE NOT NULL,
    status session_status DEFAULT 'active',
    duration_minutes INTEGER DEFAULT 5,
    session_units INTEGER DEFAULT 1 CHECK (session_units >= 1 AND session_units <= 3),
    started_at TIMESTAMPTZ DEFAULT NOW(),
    ends_at TIMESTAMPTZ NOT NULL,
    closed_at TIMESTAMPTZ,
    qr_payload TEXT,
    host_latitude DOUBLE PRECISION,
    host_longitude DOUBLE PRECISION,
    radius_meters INTEGER DEFAULT 100
);

CREATE INDEX idx_sessions_status ON attendance_sessions(status);
CREATE INDEX idx_sessions_class ON attendance_sessions(class_id);

CREATE TABLE attendance_records (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id VARCHAR(50) REFERENCES attendance_sessions(id),
    class_id VARCHAR(50),
    student_id UUID REFERENCES users(id),
    status attendance_status NOT NULL,
    match_confidence DOUBLE PRECISION,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    geo_valid BOOLEAN,
    wifi_valid BOOLEAN,
    device_valid BOOLEAN,
    liveness_passed BOOLEAN,
    rejection_reason TEXT,
    manual_note TEXT,
    updated_by UUID REFERENCES users(id),
    updated_at TIMESTAMPTZ,
    marked_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(session_id, student_id)
);

CREATE INDEX idx_attendance_student ON attendance_records(student_id);
CREATE INDEX idx_attendance_session ON attendance_records(session_id);

CREATE TABLE fraud_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id),
    session_id VARCHAR(50),
    attempt_type VARCHAR(100) NOT NULL,
    details JSONB,
    ip_address VARCHAR(45),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id),
    action VARCHAR(100) NOT NULL,
    resource_type VARCHAR(50),
    resource_id VARCHAR(100),
    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE session_sequence (
    prefix VARCHAR(20) PRIMARY KEY,
    last_number INTEGER DEFAULT 0
);

INSERT INTO session_sequence (prefix, last_number) VALUES ('ATT', 0);
