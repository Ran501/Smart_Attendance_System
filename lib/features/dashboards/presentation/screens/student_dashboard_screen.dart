import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../../../../core/config/api_config.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../../services/attendance_service.dart';
import '../../../../services/catalog_service.dart';
import '../../../../services/face_registration_service.dart';
import '../../../../services/geo_fence_service.dart';
import '../../../../widgets/app_button.dart';
import '../../../../widgets/enterprise_shell.dart';
import '../../../../widgets/session_timer.dart';

class StudentDashboardScreen extends ConsumerStatefulWidget {
  const StudentDashboardScreen({super.key});

  @override
  ConsumerState<StudentDashboardScreen> createState() => _StudentDashboardScreenState();
}

class _StudentDashboardScreenState extends ConsumerState<StudentDashboardScreen> {
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
    _locationRefreshTimer = Timer.periodic(const Duration(seconds: 8), (_) => _loadActiveSessions());
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
    _socket!.on('attendance:updated', (_) => _load());
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
            content: Text(e.toString().contains('404')
                ? 'Could not load sessions. Restart the backend (npm start in backend/).'
                : 'Could not load sessions: $e'),
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
        const SnackBar(content: Text('Register your face before marking attendance'), backgroundColor: Colors.orange),
      );
      return;
    }

    if (session['within_radius'] != true) {
      final dist = session['distance_meters'] as num?;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(dist != null
              ? 'Move closer to your teacher (${dist.toStringAsFixed(0)}m away)'
              : 'Enable GPS and stand next to your teacher'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (session['already_marked'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You already marked attendance for this session')));
      return;
    }

    context.push('/live-auth', extra: {
      'sessionId': session['id'],
      'sessionToken': session['session_token'],
      'session': session,
    });
  }

  Future<void> _showJoinModuleSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _JoinModuleSheet(onJoined: _load),
    );
  }

  double _percentage() {
    final raw = _stats?['percentage'] ?? _stats?['overallPercentage'] ?? _stats?['attendance_percentage'];
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? 0;
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  String _initial(String? name) {
    final clean = (name ?? '').trim();
    return clean.isEmpty ? 'S' : clean[0].toUpperCase();
  }

  List<Map<String, dynamic>> _modules() {
    final candidates = [_stats?['modules'], _stats?['moduleStats'], _stats?['subjects'], _stats?['classes']];
    for (final item in candidates) {
      if (item is List) return item.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }
    final total = _stats?['total'] ?? 0;
    if (total is num && total > 0) {
      return [
        {
          'name': 'Overall Attendance',
          'teacher_name': 'Academic Office',
          'percentage': _percentage(),
          'attended': _stats?['present'] ?? 0,
          'total': total,
          'medical_leave': _stats?['medicalLeave'] ?? _stats?['medical_leave'] ?? 0,
          'official_leave': _stats?['officialLeave'] ?? _stats?['official_leave'] ?? 0,
          'absent': _stats?['absent'] ?? _stats?['rejected'] ?? 0,
        }
      ];
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final percentage = _percentage();
    return EnterpriseScaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_none_rounded),
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notification center will use the existing realtime channel.'))),
          ),
          IconButton(
            tooltip: 'Theme',
            icon: Icon(ref.watch(themeModeProvider) == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode),
            onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
          ),
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(authStateProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showJoinModuleSheet,
        icon: const Icon(Icons.add),
        label: const Text('Join Module'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 94, 16, 110),
          children: [
            _StudentHero(
              name: user?.fullName ?? 'Student',
              subtitle: user?.studentId ?? user?.email ?? '',
              greeting: _greeting(),
              initial: _initial(user?.fullName),
              percentage: percentage,
              faceRegistered: _faceRegistered,
              onFaceRegister: () => context.push('/face-register'),
            ).animate().fadeIn(duration: 450.ms).slideY(begin: 0.04),
            const SizedBox(height: 18),
            if (_activeSessions.isNotEmpty)
              ..._activeSessions.map((session) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _LiveSessionBanner(session: session, loading: _loadingSessions, onMark: () => _markAttendance(session)),
                  )),
            if (_activeSessions.isEmpty)
              GlassCard(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.sensors_off_outlined, color: Theme.of(context).colorScheme.outline),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _loadingSessions ? 'Checking for live attendance sessions...' : 'No live session currently active.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    if (_loadingSessions) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  ],
                ),
              ),
            const SizedBox(height: 24),
            const SectionTitle(title: 'My Modules'),
            const SizedBox(height: 14),
            if (_modules().isEmpty)
              GlassCard(
                child: Column(
                  children: [
                    Icon(Icons.menu_book_outlined, size: 42, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 12),
                    Text('No module records found yet.', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    const Text('Join a module or wait for your teacher to enrol your class.'),
                  ],
                ),
              )
            else
              ..._modules().map((m) => _ModuleAttendanceCard(data: m, onTap: () => context.push('/module-details', extra: m)).animate().fadeIn(duration: 400.ms)),
            const SizedBox(height: 24),
            const SectionTitle(title: 'Quick Actions'),
            const SizedBox(height: 14),
            ResponsiveGrid(
              minItemWidth: 170,
              childAspectRatio: 1.22,
              children: [
                MetricTile(label: 'Present', value: '${_stats?['present'] ?? 0}', icon: Icons.check_circle_outline, color: const Color(0xFF10B981)),
                MetricTile(label: 'Absent/Rejected', value: '${_stats?['absent'] ?? _stats?['rejected'] ?? 0}', icon: Icons.cancel_outlined, color: const Color(0xFFEF4444)),
                MetricTile(label: 'Medical Leave', value: '${_stats?['medicalLeave'] ?? _stats?['medical_leave'] ?? 0}', icon: Icons.medical_services_outlined, color: const Color(0xFF3B82F6)),
                MetricTile(label: 'Total Records', value: '${_stats?['total'] ?? 0}', icon: Icons.list_alt_outlined),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: AppButton(label: 'QR Backup', icon: Icons.qr_code_scanner, outlined: true, onPressed: _faceRegistered ? () => context.push('/qr-scan') : null)),
                const SizedBox(width: 10),
                Expanded(child: AppButton(label: 'History', icon: Icons.history, outlined: true, onPressed: () => context.push('/history'))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


class _JoinModuleSheet extends StatefulWidget {
  final Future<void> Function() onJoined;

  const _JoinModuleSheet({required this.onJoined});

  @override
  State<_JoinModuleSheet> createState() => _JoinModuleSheetState();
}

class _JoinModuleSheetState extends State<_JoinModuleSheet> {
  final _moduleId = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _moduleId.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (_loading) return;
    if (_moduleId.text.trim().isEmpty || _password.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter module ID and password')));
      return;
    }

    setState(() => _loading = true);
    var joined = false;
    try {
      await CatalogService().joinModule(moduleId: _moduleId.text.trim(), password: _password.text);
      joined = true;
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Module joined successfully'), backgroundColor: Colors.green),
      );
      await widget.onJoined();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not join module: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted && !joined) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: GlassCard(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.add_circle_outline),
                const SizedBox(width: 10),
                Expanded(child: Text('Join Module', style: Theme.of(context).textTheme.titleLarge)),
              ],
            ),
            const SizedBox(height: 18),
            TextField(controller: _moduleId, decoration: const InputDecoration(labelText: 'Module ID', prefixIcon: Icon(Icons.tag_outlined))),
            const SizedBox(height: 12),
            TextField(controller: _password, decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock_outline)), obscureText: true),
            const SizedBox(height: 16),
            AppButton(
              label: 'Join Module',
              icon: Icons.login_rounded,
              loading: _loading,
              onPressed: _join,
            ),
          ],
        ),
      ),
    );
  }
}

class _StudentHero extends StatelessWidget {
  final String name;
  final String subtitle;
  final String greeting;
  final String initial;
  final double percentage;
  final bool faceRegistered;
  final VoidCallback onFaceRegister;

  const _StudentHero({
    required this.name,
    required this.subtitle,
    required this.greeting,
    required this.initial,
    required this.percentage,
    required this.faceRegistered,
    required this.onFaceRegister,
  });

  @override
  Widget build(BuildContext context) {
    final color = percentage >= 90
        ? const Color(0xFF10B981)
        : percentage >= 80
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEF4444);

    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            child: Text(initial, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$greeting, ${name.split(' ').first}', style: Theme.of(context).textTheme.titleLarge),
                if (subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
                if (!faceRegistered) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 36,
                    child: AppButton(
                      label: 'Register Face',
                      icon: Icons.face,
                      outlined: true,
                      onPressed: onFaceRegister,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${percentage.toStringAsFixed(0)}%', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color, fontWeight: FontWeight.w900)),
                Text('Attendance', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveSessionBanner extends StatelessWidget {
  final Map<String, dynamic> session;
  final bool loading;
  final VoidCallback onMark;

  const _LiveSessionBanner({required this.session, required this.loading, required this.onMark});

  DateTime _endsAt() {
    final raw = session['ends_at'] ?? session['endsAt'];
    if (raw is String) return DateTime.tryParse(raw) ?? DateTime.now().add(const Duration(minutes: 5));
    return DateTime.now().add(const Duration(minutes: 5));
  }

  @override
  Widget build(BuildContext context) {
    final within = session['within_radius'] == true;
    final marked = session['already_marked'] == true;
    final subject = session['subject_name'] as String? ?? session['subjectName'] as String? ?? 'Active Class';
    final teacher = session['teacher_name'] as String? ?? 'Teacher';

    return GlassCard(
      padding: const EdgeInsets.all(18),
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
      border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.30)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 12, height: 12, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)).animate(onPlay: (c) => c.repeat()).scale(begin: const Offset(0.85, 0.85), end: const Offset(1.25, 1.25), duration: 850.ms).fadeIn(),
              const SizedBox(width: 10),
              Expanded(child: Text('Attendance Session Active', style: Theme.of(context).textTheme.titleMedium)),
              SessionTimer(endsAt: _endsAt()),
            ],
          ),
          const SizedBox(height: 10),
          Text(subject, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text('$teacher • Face + BLE + WiFi + Location verification', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: StatusPill(
                  label: marked ? 'Already Marked' : within ? 'Inside Range' : 'Move Closer',
                  icon: marked ? Icons.check_circle : within ? Icons.my_location : Icons.location_off_outlined,
                  color: marked ? const Color(0xFF10B981) : within ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: marked || !within || loading ? null : onMark,
                icon: const Icon(Icons.face_retouching_natural),
                label: Text(marked ? 'Done' : 'Mark Attendance'),
              ).animate(onPlay: (c) => c.repeat(reverse: true)).shimmer(duration: 1800.ms, color: Colors.white.withValues(alpha: 0.22)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModuleAttendanceCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  const _ModuleAttendanceCard({required this.data, required this.onTap});

  double _numValue(List<String> keys, [double fallback = 0]) {
    for (final key in keys) {
      final raw = data[key];
      if (raw is num) return raw.toDouble();
      final parsed = double.tryParse(raw?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final name = data['name'] ?? data['moduleName'] ?? data['subject_name'] ?? data['subjectName'] ?? 'Module';
    final teacher = data['teacher_name'] ?? data['teacherName'] ?? data['teacher'] ?? 'Teacher';
    final percentage = _numValue(['percentage', 'attendancePercentage', 'attendance_percentage']);
    final attended = _numValue(['attended', 'present', 'classesAttended']).toInt();
    final total = _numValue(['total', 'classesTotal', 'totalClasses']).toInt();
    final medical = _numValue(['medical_leave', 'medicalLeave']).toInt();
    final official = _numValue(['official_leave', 'officialLeave']).toInt();
    final absent = _numValue(['absent', 'rejected']).toInt();
    final color = percentage >= 90 ? const Color(0xFF10B981) : percentage >= 80 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GlassCard(
        onTap: onTap,
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name.toString(), style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text(teacher.toString(), style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                AttendanceLiquidGauge(percentage: percentage, size: 88, compact: true),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(value: (percentage / 100).clamp(0.0, 1.0).toDouble(), minHeight: 8, color: color, backgroundColor: color.withValues(alpha: 0.12)),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MiniCount(label: 'Attended', value: total > 0 ? '$attended/$total' : '$attended', color: const Color(0xFF10B981)),
                _MiniCount(label: 'Medical', value: '$medical', color: const Color(0xFF3B82F6)),
                _MiniCount(label: 'Official', value: '$official', color: const Color(0xFF8B5CF6)),
                _MiniCount(label: 'Absent', value: '$absent', color: const Color(0xFFEF4444)),
                _MiniCount(label: 'Risk', value: percentage >= 90 ? 'Low' : percentage >= 80 ? 'Medium' : 'High', color: color),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniCount extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniCount({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14)),
      child: Text('$label: $value', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
    );
  }
}
