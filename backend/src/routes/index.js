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
const notificationController = require('../controllers/notificationController');
const { asyncHandler } = require('../utils/asyncHandler');

const router = express.Router();

const schedulePlanBodyRules = [
  body('semesterTotalHours')
    .custom((value) => {
      const n = parseInt(value, 10);
      if (Number.isNaN(n) || n < 1 || n > 500) {
        throw new Error('semesterTotalHours must be between 1 and 500');
      }
      return true;
    }),
  body('hoursPerWeek')
    .custom((value) => {
      const n = parseFloat(value);
      if (Number.isNaN(n) || n < 0.5 || n > 80) {
        throw new Error('hoursPerWeek must be between 0.5 and 80');
      }
      return true;
    }),
];

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
router.get('/modules/student', authenticate, authorize('student'), moduleController.listStudentModules);
router.get('/student/modules', authenticate, authorize('student'), moduleController.listStudentModules);
router.get('/modules/enrolled', authenticate, authorize('student'), moduleController.listStudentModules);
router.get('/classes/student', authenticate, authorize('student'), moduleController.listStudentModules);
router.get('/classes/enrolled', authenticate, authorize('student'), moduleController.listStudentModules);
router.get('/enrolments/modules', authenticate, authorize('student'), moduleController.listStudentModules);
router.get('/enrollments/modules', authenticate, authorize('student'), moduleController.listStudentModules);
router.post('/modules', authenticate, authorize('teacher', 'admin'), moduleController.createModule);
router.post('/modules/create', authenticate, authorize('teacher', 'admin'), moduleController.createModule);
router.post('/modules/join', authenticate, authorize('student'), moduleController.joinModule);
router.get('/modules/:moduleId/sessions', authenticate, moduleController.getModuleSessions);
router.get('/subjects/:subjectId/attendance', authenticate, authorize('student'), moduleController.getStudentModuleAttendance);
router.get('/modules/:moduleId/attendance', authenticate, authorize('student'), moduleController.getStudentModuleAttendance);
router.get('/classes/:classId/attendance', authenticate, authorize('student'), moduleController.getStudentModuleAttendance);
router.get('/modules/:moduleId/summary', authenticate, moduleController.getModuleSummary);
router.get(
  '/modules/:moduleId/attendance-plan',
  authenticate,
  asyncHandler(moduleController.getAttendancePlan),
);
router.put(
  '/modules/:moduleId/attendance-plan',
  authenticate,
  authorize('teacher', 'admin'),
  schedulePlanBodyRules,
  validate,
  asyncHandler(moduleController.updateAttendancePlan),
);
router.post(
  '/modules/:moduleId/attendance-plan',
  authenticate,
  authorize('teacher', 'admin'),
  schedulePlanBodyRules,
  validate,
  asyncHandler(moduleController.updateAttendancePlan),
);
const scheduleAdjustmentRules = [
  body('type')
    .optional()
    .isIn(['extra', 'extra_class', 'extra-class', 'cancelled', 'cancelled_class', 'cancelled-class', 'no_class', 'no-class', 'noclass']),
  body('extraClasses')
    .optional()
    .custom((value) => {
      if (value === undefined || value === null || value === '') return true;
      const n = parseInt(value, 10);
      if (Number.isNaN(n) || n < 0 || n > 200) {
        throw new Error('extraClasses must be between 0 and 200');
      }
      return true;
    }),
  body('cancelledClasses')
    .optional()
    .custom((value) => {
      if (value === undefined || value === null || value === '') return true;
      const n = parseInt(value, 10);
      if (Number.isNaN(n) || n < 0 || n > 200) {
        throw new Error('cancelledClasses must be between 0 and 200');
      }
      return true;
    }),
];

router.post(
  '/modules/:moduleId/attendance-plan/adjustments',
  authenticate,
  authorize('teacher', 'admin'),
  scheduleAdjustmentRules,
  validate,
  asyncHandler(moduleController.recordAttendanceAdjustment),
);

// Sessions (teacher)
router.post(
  '/sessions',
  authenticate,
  authorize('teacher', 'admin'),
  [
    body('classId').notEmpty(),
    body('subjectId').notEmpty(),
    body('classroomId').notEmpty(),
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
router.get('/sessions/student/module/:moduleId', authenticate, authorize('student'), moduleController.getModuleSessions);
router.get('/student/modules/:moduleId/sessions', authenticate, authorize('student'), moduleController.getModuleSessions);
router.get('/classes/:classId/sessions', authenticate, moduleController.getModuleSessions);
router.get('/sessions', authenticate, moduleController.getModuleSessions);
router.get('/sessions/:sessionId', authenticate, sessionController.getSession);
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

// Attendance (student + teacher manual edits)
router.post('/attendance/submit', authenticate, authorize('student'), attendanceController.submitAttendance);
router.get('/attendance/history', authenticate, authorize('student'), attendanceController.getStudentHistory);
router.get('/attendance/module/:moduleId', authenticate, authorize('student'), moduleController.getStudentModuleAttendance);
router.get('/attendance/history/module/:moduleId', authenticate, authorize('student'), moduleController.getStudentModuleAttendance);
router.get('/attendance/stats', authenticate, authorize('student'), attendanceController.getStudentStats);
router.post('/attendance/update', authenticate, authorize('teacher', 'admin'), attendanceController.updateAttendanceStatus);
router.patch('/attendance/:recordId/status', authenticate, authorize('teacher', 'admin'), attendanceController.updateAttendanceStatus);
router.patch('/attendance/:recordId', authenticate, authorize('teacher', 'admin'), attendanceController.updateAttendanceStatus);
router.patch('/attendance/records/:recordId', authenticate, authorize('teacher', 'admin'), attendanceController.updateAttendanceStatus);

// Notifications
router.post('/device/token', authenticate, notificationController.registerToken);
router.get('/notifications', authenticate, notificationController.listNotifications);
router.get('/notifications/unread-count', authenticate, notificationController.unreadCount);
router.patch('/notifications/:id/read', authenticate, notificationController.markRead);

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
