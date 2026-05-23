import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../widgets/app_brand_logo.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), _navigate);
  }

  void _navigate() {
    if (!mounted) return;
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) {
      context.go('/login');
    } else if (user.isTeacher) {
      context.go('/teacher');
    } else {
      context.go('/student');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0D3B16),
                  Color(0xFF1B5E20),
                  Color(0xFF2E7D32),
                  Color(0xFF43A047),
                ],
                stops: [0.0, 0.35, 0.7, 1.0],
              ),
            ),
          ),
          ..._backgroundOrbs(),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppBrandLogo.splash()
                      .animate()
                      .fadeIn(duration: 600.ms)
                      .scale(
                        begin: const Offset(0.88, 0.88),
                        end: const Offset(1, 1),
                        curve: Curves.easeOutBack,
                      ),
                  const SizedBox(height: 32),
                  Text(
                    AppConstants.appName,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                  )
                      .animate()
                      .fadeIn(delay: 200.ms, duration: 500.ms)
                      .slideY(begin: 0.15, end: 0),
                  const SizedBox(height: 10),
                  Text(
                    AppConstants.appTagline,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 350.ms, duration: 500.ms)
                      .slideY(begin: 0.1, end: 0),
                  const SizedBox(height: 48),
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Colors.white.withValues(alpha: 0.95),
                    ),
                  ).animate().fadeIn(delay: 500.ms),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _backgroundOrbs() {
    return [
      Positioned(
        top: -80,
        right: -40,
        child: _orb(220, Colors.white.withValues(alpha: 0.07)),
      ),
      Positioned(
        bottom: -100,
        left: -60,
        child: _orb(280, const Color(0xFF81C784).withValues(alpha: 0.2)),
      ),
      Positioned(
        top: 120,
        left: -30,
        child: _orb(140, Colors.white.withValues(alpha: 0.06)),
      ),
    ];
  }

  Widget _orb(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}
