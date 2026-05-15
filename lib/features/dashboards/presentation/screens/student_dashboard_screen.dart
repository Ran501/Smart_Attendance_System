import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../../services/attendance_service.dart';
import '../../../../services/face_registration_service.dart';
import '../../../../widgets/app_button.dart';
import '../../../../widgets/stat_card.dart';

class StudentDashboardScreen extends ConsumerStatefulWidget {
  const StudentDashboardScreen({super.key});

  @override
  ConsumerState<StudentDashboardScreen> createState() => _StudentDashboardScreenState();
}

class _StudentDashboardScreenState extends ConsumerState<StudentDashboardScreen> {
  Map<String, dynamic>? _stats;
  bool _faceRegistered = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final stats = await AttendanceService().getStats();
      final registered = await FaceRegistrationService().isFaceRegistered();
      if (mounted) setState(() {
        _stats = stats;
        _faceRegistered = registered;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Dashboard'),
        actions: [
          IconButton(
            icon: Icon(ref.watch(themeModeProvider) == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode),
            onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(authStateProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: CircleAvatar(child: Text(user?.fullName.substring(0, 1) ?? 'S')),
                title: Text(user?.fullName ?? ''),
                subtitle: Text(user?.studentId ?? user?.email ?? ''),
              ),
            ),
            if (!_faceRegistered)
              Card(
                color: Colors.orange.shade50,
                child: ListTile(
                  leading: const Icon(Icons.warning_amber, color: Colors.orange),
                  title: const Text('Face not registered'),
                  subtitle: const Text('Register your face before marking attendance'),
                  trailing: TextButton(
                    onPressed: () => context.push('/face-register'),
                    child: const Text('Register'),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.3,
              children: [
                StatCard(
                  title: 'Attendance %',
                  value: '${_stats?['percentage'] ?? '0'}%',
                  icon: Icons.pie_chart,
                ),
                StatCard(
                  title: 'Present',
                  value: '${_stats?['present'] ?? 0}',
                  icon: Icons.check_circle,
                  color: Colors.green,
                ),
                StatCard(
                  title: 'Rejected',
                  value: '${_stats?['rejected'] ?? 0}',
                  icon: Icons.cancel,
                  color: Colors.red,
                ),
                StatCard(
                  title: 'Total',
                  value: '${_stats?['total'] ?? 0}',
                  icon: Icons.list_alt,
                ),
              ],
            ),
            const SizedBox(height: 24),
            AppButton(
              label: 'Mark Attendance (Scan QR)',
              icon: Icons.qr_code_scanner,
              onPressed: _faceRegistered ? () => context.push('/qr-scan') : null,
            ),
            const SizedBox(height: 12),
            AppButton(
              label: 'Register Face',
              icon: Icons.face,
              outlined: true,
              onPressed: () => context.push('/face-register'),
            ),
            const SizedBox(height: 12),
            AppButton(
              label: 'Attendance History',
              icon: Icons.history,
              outlined: true,
              onPressed: () => context.push('/history'),
            ),
          ],
        ),
      ),
    );
  }
}
