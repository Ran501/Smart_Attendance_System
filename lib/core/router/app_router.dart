import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/authentication/presentation/screens/login_screen.dart';
import '../../features/authentication/presentation/screens/register_screen.dart';
import '../../features/authentication/presentation/screens/splash_screen.dart';
import '../../features/face_recognition/presentation/screens/face_registration_screen.dart';
import '../../features/attendance/presentation/screens/qr_scan_screen.dart';
import '../../features/attendance/presentation/screens/live_auth_screen.dart';
import '../../features/attendance/presentation/screens/attendance_session_screen.dart';
import '../../features/dashboards/presentation/screens/student_dashboard_screen.dart';
import '../../features/dashboards/presentation/screens/teacher_dashboard_screen.dart';
import '../../features/dashboards/presentation/screens/admin_dashboard_screen.dart';
import '../../features/dashboards/presentation/screens/analytics_screen.dart';
import '../../features/dashboards/presentation/screens/attendance_history_screen.dart';
import '../providers/auth_provider.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final isLoggedIn = authState.valueOrNull != null;
      final isAuthRoute = state.matchedLocation == '/login' ||
          state.matchedLocation == '/register' ||
          state.matchedLocation == '/';

      if (!isLoggedIn && !isAuthRoute) return '/login';
      if (isLoggedIn && (state.matchedLocation == '/login' || state.matchedLocation == '/')) {
        final role = authState.valueOrNull?.role;
        switch (role) {
          case 'teacher':
            return '/teacher';
          case 'admin':
            return '/admin';
          default:
            return '/student';
        }
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/student', builder: (_, __) => const StudentDashboardScreen()),
      GoRoute(path: '/teacher', builder: (_, __) => const TeacherDashboardScreen()),
      GoRoute(path: '/admin', builder: (_, __) => const AdminDashboardScreen()),
      GoRoute(path: '/face-register', builder: (_, __) => const FaceRegistrationScreen()),
      GoRoute(path: '/qr-scan', builder: (_, __) => const QrScanScreen()),
      GoRoute(
        path: '/live-auth',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return LiveAuthScreen(sessionData: extra ?? {});
        },
      ),
      GoRoute(
        path: '/session/:id',
        builder: (_, state) => AttendanceSessionScreen(
          sessionId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(path: '/analytics', builder: (_, __) => const AnalyticsScreen()),
      GoRoute(path: '/history', builder: (_, __) => const AttendanceHistoryScreen()),
    ],
  );
});
