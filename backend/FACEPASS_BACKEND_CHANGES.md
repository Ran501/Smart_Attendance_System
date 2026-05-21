# FacePass Bhutan Backend Changes

This backend update connects the new Flutter UI changes to the existing PostgreSQL database flow.

## Added/updated API support

### Modules
- `GET /api/v1/modules/teacher`
- `GET /api/v1/teacher/modules`
- `GET /api/v1/modules`
- `POST /api/v1/modules`
- `POST /api/v1/modules/create`
- `POST /api/v1/classes`
- `POST /api/v1/classes/create`
- `POST /api/v1/modules/join`
- `POST /api/v1/classes/join`

Teacher module creation stores the module in the existing `subjects` table and creates/uses a class in the existing `classes` table. Join passwords are stored as hashes in `subjects.join_password_hash`.

### Module sessions and analytics
- `GET /api/v1/modules/:moduleId/sessions`
- `GET /api/v1/subjects/:subjectId/sessions`
- `GET /api/v1/sessions/module/:moduleId`
- `GET /api/v1/sessions?moduleId=...`
- `GET /api/v1/analytics/teacher?moduleId=...`

These return only the selected module sessions, matching the new top-bar analytics flow.

### Block-period session count
`POST /api/v1/sessions` now accepts:
- `sessionUnits`
- `session_units`
- `periodCount`
- `blockPeriods`

Values are clamped to 1, 2, or 3. Only one attendance session is created, but it counts as multiple sessions in summaries.

### Session roster and manual edit
- `GET /api/v1/sessions/:sessionId/roster`
- `GET /api/v1/sessions/:sessionId/attendance?includeAll=true`
- `PATCH /api/v1/sessions/:sessionId/attendance/:studentId`
- `PATCH /api/v1/attendance/:recordId/status`
- `PATCH /api/v1/attendance/:recordId`
- `PATCH /api/v1/attendance/records/:recordId`
- `POST /api/v1/attendance/update`

Teachers can change records to:
- `PRESENT`
- `ABSENT`
- `MEDICAL_LEAVE`
- `OFFICIAL_LEAVE`
- `REJECTED`

The roster returns all enrolled students. Students without a marked record are returned as `ABSENT`.

### Reports
- `GET /api/v1/reports/session/:sessionId`
- `GET /api/v1/reports/module/:moduleId`

## Database migration

Run this once on your existing database:

```bash
npm run db:migrate:facepass
```

or:

```bash
node src/database/run-migration.js 003_facepass_module_flow.sql
```

The migration adds:
- `MEDICAL_LEAVE` and `OFFICIAL_LEAVE` enum values
- `subjects.join_password_hash`
- `attendance_sessions.session_units`
- `attendance_records.manual_note`
- `attendance_records.updated_by`
- `attendance_records.updated_at`

## Important

The original `.env` file is not included in this zip for safety. Copy your existing `.env` back into the backend folder before running.
