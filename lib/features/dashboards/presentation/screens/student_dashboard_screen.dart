import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../../../../core/config/api_config.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../../services/attendance_service.dart';
import '../../../../services/face_registration_service.dart';
import '../../../../services/geo_fence_service.dart';
import '../../../../widgets/app_button.dart';
import '../../../../widgets/stat_card.dart';

class StudentDashboardScreen extends ConsumerStatefulWidget {
  const StudentDashboardScreen({super.key});

  @override
  ConsumerState<StudentDashboardScreen> createState() =>
      _StudentDashboardScreenState();
}

class _StudentDashboardScreenState
    extends ConsumerState<StudentDashboardScreen> {
  Map<String, dynamic>? _stats;
  bool _faceRegistered = false;
  List<Map<String, dynamic>> _activeSessions = [];
  List<String> _enrolledClassIds = [];
  bool _loadingSessions = false;
  io.Socket? _socket;
  Timer? _locationRefreshTimer;
  final _geo = GeoFenceService();

  @override
  void initState() {
    super.initState();
    _load();
    _connectSocket();
    _locationRefreshTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _loadActiveSessions(),
    );
  }

  @override
  void dispose() {
    _locationRefreshTimer?.cancel();
    _socket?.disconnect();
    _socket?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final stats = await AttendanceService().getStats();
      final registered = await FaceRegistrationService().isFaceRegistered();
      if (mounted) {
        setState(() {
          _stats = stats;
          _faceRegistered = registered;
        });
      }
    } catch (_) {}
    await _loadActiveSessions();
  }

  void _connectSocket() {
    final baseUrl = ApiConfig.baseUrl.replaceAll('/api/v1', '');
    _socket = io.io(baseUrl, io.OptionBuilder().setTransports(['websocket']).build());
    _socket!.connect();
    _socket!.on('session:started', (_) => _loadActiveSessions());
    _socket!.on('session:closed', (_) => _loadActiveSessions());
  }

  void _joinClassRooms() {
    for (final id in _enrolledClassIds) {
      _socket?.emit('join:class', id);
    }
  }

  Future<void> _loadActiveSessions() async {
    if (!mounted) return;
    setState(() => _loadingSessions = true);
    try {
      Position? position;
      try {
        position = await _geo.getBestPosition(maxSamples: 3);
      } catch (_) {}

      final result = await AttendanceService().getStudentActiveSessions(
        latitude: position?.latitude,
        longitude: position?.longitude,
        accuracy: position?.accuracy,
      );
      if (mounted) {
        setState(() {
          _activeSessions = result.sessions;
          _enrolledClassIds = result.enrolledClassIds;
        });
        _joinClassRooms();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _activeSessions = []);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString().contains('404')
                  ? 'Could not load sessions. Restart the backend (npm start in backend/).'
                  : 'Could not load sessions: $e',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingSessions = false);
    }
  }

  Future<void> _markAttendance(Map<String, dynamic> session) async {
    if (!_faceRegistered) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Register your face before marking attendance'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (session['within_radius'] != true) {
      final dist = session['distance_meters'] as num?;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dist != null
                ? 'Move closer to your teacher (${dist.toStringAsFixed(0)}m away)'
                : 'Enable GPS and stand next to your teacher',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (session['already_marked'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You already marked attendance for this session')),
      );
      return;
    }

    context.push(
      '/live-auth',
      extra: {
        'sessionId': session['id'],
        'sessionToken': session['session_token'],
        'session': session,
      },
    );
  }

  Widget _buildSessionCard(Map<String, dynamic> session) {
    final within = session['within_radius'] == true;
    final dist = session['distance_meters'] as num?;
    final marked = session['already_marked'] == true;
    final allowed = session['allowed_radius_meters'] as num?;
    final radius = session['radius_meters'] as num? ?? 100;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  within ? Icons.location_on : Icons.location_off,
                  color: within ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    session['subject_name'] as String? ?? 'Active session',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (marked)
                  const Chip(
                    label: Text('Done'),
                    backgroundColor: Colors.green,
                    labelStyle: TextStyle(color: Colors.white, fontSize: 12),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${session['class_name'] ?? ''} • ${session['teacher_name'] ?? 'Teacher'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              dist != null
                  ? 'Distance: ${dist.toStringAsFixed(1)}m (allowed ~${(allowed ?? radius).toStringAsFixed(0)}m incl. GPS buffer)'
                  : 'Turn on GPS to check distance to teacher',
              style: TextStyle(
                color: within ? Colors.green.shade700 : Colors.orange.shade800,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            AppButton(
              label: marked
                  ? 'Attendance marked'
                  : within
                      ? 'Mark attendance'
                      : 'Move closer',
              icon: Icons.face_retouching_natural,
              onPressed: marked || !within
                  ? null
                  : () => _markAttendance(session),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Dashboard'),
        actions: [
          IconButton(
            icon: Icon(
              ref.watch(themeModeProvider) == ThemeMode.dark
                  ? Icons.light_mode
                  : Icons.dark_mode,
            ),
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
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(user?.fullName.substring(0, 1) ?? 'S'),
                      ),
                      title: Text(user?.fullName ?? ''),
                      subtitle: Text(user?.studentId ?? user?.email ?? ''),
                    ),
                  ),
                  if (!_faceRegistered)
                    Card(
                      color: Colors.orange.shade50,
                      child: ListTile(
                        leading: const Icon(
                          Icons.warning_amber,
                          color: Colors.orange,
                        ),
                        title: const Text('Face not registered'),
                        subtitle: const Text(
                          'Register your face before marking attendance',
                        ),
                        trailing: TextButton(
                          onPressed: () => context.push('/face-register'),
                          child: const Text('Register'),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        'Live sessions',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Spacer(),
                      if (_loadingSessions)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Sessions appear when your teacher starts class. Stand near your teacher — GPS buffer is applied automatically.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  if (_activeSessions.isEmpty && !_loadingSessions)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No active sessions right now. Ask your teacher to start one.',
                        ),
                      ),
                    )
                  else
                    ..._activeSessions.map(_buildSessionCard),
                  const SizedBox(height: 16),
                ]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate((context, index) {
                  const items = [
                    ['Attendance %', Icons.pie_chart, null],
                    ['Present', Icons.check_circle, Colors.green],
                    ['Rejected', Icons.cancel, Colors.red],
                    ['Total', Icons.list_alt, null],
                  ];
                  final item = items[index];
                  String value;
                  switch (index) {
                    case 0:
                      value = '${_stats?['percentage'] ?? '0'}%';
                      break;
                    case 1:
                      value = '${_stats?['present'] ?? 0}';
                      break;
                    case 2:
                      value = '${_stats?['rejected'] ?? 0}';
                      break;
                    default:
                      value = '${_stats?['total'] ?? 0}';
                  }
                  return StatCard(
                    title: item[0] as String,
                    value: value,
                    icon: item[1] as IconData,
                    color: item[2] as Color?,
                  );
                }, childCount: 4),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.1,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  AppButton(
                    label: 'Scan QR (alternative)',
                    icon: Icons.qr_code_scanner,
                    outlined: true,
                    onPressed: _faceRegistered
                        ? () => context.push('/qr-scan')
                        : null,
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
                  SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
