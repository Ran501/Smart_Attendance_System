import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/authentication/presentation/screens/login_screen.dart';
import '../../features/authentication/presentation/screens/register_screen.dart';
import '../../features/authentication/presentation/screens/splash_screen.dart';
import '../../features/face_recognition/presentation/screens/face_registration_screen.dart';
import '../../features/attendance/presentation/screens/live_auth_screen.dart';
import '../../features/attendance/presentation/screens/attendance_session_screen.dart';
import '../../features/dashboards/presentation/screens/student_dashboard_screen.dart';
import '../../features/dashboards/presentation/screens/teacher_dashboard_screen.dart';
import '../../features/dashboards/presentation/screens/analytics_screen.dart';
import '../../features/dashboards/presentation/screens/attendance_history_screen.dart';
import '../../features/dashboards/presentation/screens/module_details_screen.dart';
import '../../features/dashboards/presentation/screens/teacher_module_screen.dart';
import '../providers/auth_provider.dart';
import 'go_router_refresh.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = GoRouterRefreshNotifier(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final isLoggedIn = authState.valueOrNull != null;
      final isAuthRoute =
          state.matchedLocation == '/login' ||
          state.matchedLocation == '/register' ||
          state.matchedLocation == '/';

      if (!isLoggedIn && !isAuthRoute) return '/login';
      if (isLoggedIn &&
          (state.matchedLocation == '/login' || state.matchedLocation == '/')) {
        final role = authState.valueOrNull?.role;
        if (role == 'teacher' || role == 'admin') return '/teacher';
        return '/student';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(
        path: '/student',
        builder: (_, __) => const StudentDashboardScreen(),
      ),
      GoRoute(
        path: '/teacher',
        builder: (_, __) => const TeacherDashboardScreen(),
      ),
      GoRoute(
        path: '/face-register',
        builder: (_, __) => const FaceRegistrationScreen(),
      ),
      GoRoute(
        path: '/live-auth',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return LiveAuthScreen(sessionData: extra ?? {});
        },
      ),
      GoRoute(
        path: '/session/:id',
        builder: (_, state) =>
            AttendanceSessionScreen(sessionId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/analytics', builder: (_, __) => const AnalyticsScreen()),
      GoRoute(
        path: '/teacher-module',
        builder: (_, state) => TeacherModuleScreen(
          module: (state.extra as Map<String, dynamic>?) ?? const {},
        ),
      ),
      GoRoute(
        path: '/history',
        builder: (_, __) => const AttendanceHistoryScreen(),
      ),
      GoRoute(
        path: '/module-details',
        builder: (_, state) => ModuleDetailsScreen(
          module: (state.extra as Map<String, dynamic>?) ?? const {},
        ),
      ),
    ],
  );
});
