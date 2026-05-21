const express = require('express');
const { body } = require('express-validator');
const { authenticate, authorize } = require('../middleware/auth');
const validate = require('../middleware/validate');
const authController = require('../controllers/authController');
const faceController = require('../controllers/faceController');
const sessionController = require('../controllers/sessionController');
const attendanceController = require('../controllers/attendanceController');
const analyticsController = require('../controllers/analyticsController');
const moduleController = require('../controllers/moduleController');

const router = express.Router();

// Auth
router.post(
  '/auth/login',
  [body('email').isEmail(), body('password').notEmpty()],
  validate,
  authController.login,
);
router.post(
  '/auth/register',
  [
    body('email').isEmail().normalizeEmail(),
    body('password').isLength({ min: 8 }),
    body('fullName').trim().notEmpty(),
    body('role').isIn(['student', 'teacher', 'admin']),
    body('studentId').optional({ values: 'falsy' }).trim(),
  ],
  validate,
  authController.register,
);
router.get('/auth/me', authenticate, authController.me);

// Face & device
router.post('/face/register', authenticate, authorize('student'), faceController.registerEmbeddings);
router.get('/face/status', authenticate, faceController.getMyEmbeddings);
router.post('/face/verify', authenticate, faceController.verifyEmbedding);
router.post('/device/verify', authenticate, faceController.verifyDevice);

// Classes, subjects, classrooms, and FacePass modules
router.get('/classes', authenticate, analyticsController.getClasses);
router.post('/classes', authenticate, authorize('teacher', 'admin'), moduleController.createModule);
router.post('/classes/create', authenticate, authorize('teacher', 'admin'), moduleController.createModule);
router.post('/classes/join', authenticate, authorize('student'), moduleController.joinModule);

router.get('/subjects', authenticate, analyticsController.getSubjects);
router.get('/subjects/:subjectId/sessions', authenticate, moduleController.getModuleSessions);
router.get('/classrooms', authenticate, analyticsController.getClassrooms);

router.get('/modules', authenticate, moduleController.listTeacherModules);
router.get('/modules/teacher', authenticate, authorize('teacher', 'admin'), moduleController.listTeacherModules);
router.get('/teacher/modules', authenticate, authorize('teacher', 'admin'), moduleController.listTeacherModules);
router.post('/modules', authenticate, authorize('teacher', 'admin'), moduleController.createModule);
router.post('/modules/create', authenticate, authorize('teacher', 'admin'), moduleController.createModule);
router.post('/modules/join', authenticate, authorize('student'), moduleController.joinModule);
router.get('/modules/:moduleId/sessions', authenticate, moduleController.getModuleSessions);
router.get('/modules/:moduleId/summary', authenticate, moduleController.getModuleSummary);

// Sessions (teacher)
router.post(
  '/sessions',
  authenticate,
  authorize('teacher', 'admin'),
  [
    body('classId').notEmpty(),
    body('subjectId').notEmpty(),
    body('classroomId').notEmpty(),
    body('latitude').isFloat({ min: -90, max: 90 }),
    body('longitude').isFloat({ min: -180, max: 180 }),
    body('radiusMeters').optional().isInt({ min: 1, max: 500 }),
    body('sessionUnits').optional().isInt({ min: 1, max: 3 }),
  ],
  validate,
  sessionController.createSession,
);
router.get(
  '/sessions/active',
  authenticate,
  authorize('teacher', 'admin'),
  sessionController.getActiveSessions,
);
router.get(
  '/sessions/student/active',
  authenticate,
  authorize('student'),
  sessionController.getStudentActiveSessions,
);
router.get('/sessions/module/:moduleId', authenticate, moduleController.getModuleSessions);
router.get('/sessions', authenticate, moduleController.getModuleSessions);
router.get('/sessions/:sessionId', authenticate, sessionController.getSession);
router.patch(
  '/sessions/:sessionId/location',
  authenticate,
  authorize('teacher', 'admin'),
  [
    body('latitude').isFloat({ min: -90, max: 90 }),
    body('longitude').isFloat({ min: -180, max: 180 }),
    body('accuracy').optional().isFloat({ min: 0 }),
  ],
  validate,
  sessionController.updateSessionLocation,
);
router.post(
  '/sessions/:sessionId/close',
  authenticate,
  authorize('teacher', 'admin'),
  sessionController.closeSession,
);
router.get(
  '/sessions/:sessionId/roster',
  authenticate,
  sessionController.getSessionRoster,
);
router.get(
  '/sessions/:sessionId/attendance',
  authenticate,
  sessionController.getSessionAttendance,
);
router.patch(
  '/sessions/:sessionId/attendance/:studentId',
  authenticate,
  authorize('teacher', 'admin'),
  attendanceController.updateAttendanceStatus,
);
router.post('/sessions/validate-qr', authenticate, sessionController.validateQr);

// Attendance (student + teacher manual edits)
router.post('/attendance/submit', authenticate, authorize('student'), attendanceController.submitAttendance);
router.get('/attendance/history', authenticate, authorize('student'), attendanceController.getStudentHistory);
router.get('/attendance/stats', authenticate, authorize('student'), attendanceController.getStudentStats);
router.post('/attendance/update', authenticate, authorize('teacher', 'admin'), attendanceController.updateAttendanceStatus);
router.patch('/attendance/:recordId/status', authenticate, authorize('teacher', 'admin'), attendanceController.updateAttendanceStatus);
router.patch('/attendance/:recordId', authenticate, authorize('teacher', 'admin'), attendanceController.updateAttendanceStatus);
router.patch('/attendance/records/:recordId', authenticate, authorize('teacher', 'admin'), attendanceController.updateAttendanceStatus);

// Analytics & admin
router.get(
  '/analytics/teacher',
  authenticate,
  authorize('teacher', 'admin'),
  analyticsController.getTeacherAnalytics,
);
router.get(
  '/admin/fraud-logs',
  authenticate,
  authorize('admin'),
  analyticsController.getAdminFraudLogs,
);
router.get('/admin/users', authenticate, authorize('admin'), analyticsController.getAdminUsers);
router.get('/reports/session/:sessionId', authenticate, analyticsController.exportSessionReport);
router.get('/reports/module/:moduleId', authenticate, analyticsController.exportModuleReport);

module.exports = router;
