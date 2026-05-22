# FacePass Backend Changes

## Latest changes

- Removed QR backup attendance from the backend API.
  - Removed QR generation from session creation.
  - Removed `/sessions/validate-qr` route.
  - Removed `qrcode` dependency from `package.json` and `package-lock.json`.
  - Added migration `004_remove_qr_payload.sql` to remove the old `qr_payload` column if you want the database cleaned.

- Added student joined-module APIs for the new student dashboard.
  - `GET /modules/student`
  - `GET /student/modules`
  - `GET /modules/enrolled`
  - `GET /classes/student`
  - `GET /classes/enrolled`
  - `GET /enrolments/modules`
  - `GET /enrollments/modules`

- Added per-module student attendance report APIs.
  - `GET /attendance/module/:moduleId`
  - `GET /attendance/history/module/:moduleId`
  - `GET /modules/:moduleId/attendance`
  - `GET /subjects/:subjectId/attendance`
  - `GET /classes/:classId/attendance`

- Added module-specific session API aliases used by the Flutter frontend.
  - `GET /sessions/student/module/:moduleId`
  - `GET /student/modules/:moduleId/sessions`
  - `GET /classes/:classId/sessions`

- Updated `/attendance/stats` to include `modules` and `moduleStats`, so the frontend can show each joined module with its own progress bar instead of a fake overall module card.

- Kept the live face attendance flow compatible with the new auto-capture frontend.
  - Backend still expects `liveEmbedding`, `livenessPassed`, `sessionId`, `sessionToken`, location, and device data.
  - Extra liveness/camera fields from the app are tolerated safely because unknown request fields are ignored.

## Database migration for existing deployments

If your database already has the old QR column and you want to remove it, run:

```bash
npm run db:migrate:host -- 004_remove_qr_payload.sql
```

Or run directly:

```bash
node src/database/run-migration.js 004_remove_qr_payload.sql
```
