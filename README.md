# Smart Attendance System (FacePass Bhutan)

Flutter mobile app + cloud API (Railway + Neon PostgreSQL) for AI face attendance.

## Run the app

```bash
flutter pub get
flutter run
```

All phones use the **cloud API** automatically — no local server or URL settings.

Cloud API: `https://smartattendancesystem-production-5b56.up.railway.app`

## Demo accounts (after backend seed)

| Role    | Email                 | Password      |
|---------|-----------------------|---------------|
| Student | student@college.edu   | password123   |
| Teacher | teacher@college.edu   | password123   |

## Backend (optional — for API development only)

```bash
cd backend
cp .env.example .env
npm install
npm run db:migrate
npm run db:seed
npm start
```

Production app builds do **not** use a local backend; they always call Railway.
