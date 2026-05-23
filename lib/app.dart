import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/auth/session_auth_guard.dart';
import 'core/constants/app_constants.dart';
import 'core/providers/auth_provider.dart';
import 'core/providers/theme_provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'services/api_client.dart';

class SmartAttendanceApp extends ConsumerStatefulWidget {
  const SmartAttendanceApp({super.key});

  @override
  ConsumerState<SmartAttendanceApp> createState() => _SmartAttendanceAppState();
}

class _SmartAttendanceAppState extends ConsumerState<SmartAttendanceApp> {
  bool _reloginPromptOpen = false;

  @override
  void initState() {
    super.initState();
    SessionAuthGuard.onReloginRequired = _handleReloginRequired;
  }

  @override
  void dispose() {
    SessionAuthGuard.onReloginRequired = null;
    super.dispose();
  }

  Future<void> _handleReloginRequired() async {
    if (_reloginPromptOpen) return;
    _reloginPromptOpen = true;

    await ref.read(authStateProvider.notifier).logout();

    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) {
      _reloginPromptOpen = false;
      return;
    }

    await showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign in again'),
        content: const Text(
          'Your session could not be verified after several attempts. '
          'Please log in again to continue.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              if (ctx.mounted) ctx.go('/login');
            },
            child: const Text('Go to login'),
          ),
        ],
      ),
    );
    _reloginPromptOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
