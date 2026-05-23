import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../../../../core/config/api_config.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../../services/api_client.dart';
import '../../../../services/attendance_service.dart';
import '../../../../services/notification_service.dart';
import '../../../notifications/notification_screen.dart';
import '../../../../core/ble/ble_proximity_state.dart';
import '../../../../services/ble_proximity_monitor.dart';
import '../../../../services/catalog_service.dart';
import '../../../../services/face_registration_service.dart';
import '../../../../widgets/app_brand_logo.dart';
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
  List<Map<String, dynamic>> _joinedModules = [];
  List<String> _enrolledClassIds = [];
  bool _loadingSessions = false;
  io.Socket? _socket;
  Timer? _sessionRefreshTimer;
  int _apiSessionCount = 0;
  List<Map<String, dynamic>> _apiSessions = [];
  Map<String, BleSessionProximity> _proximity = {};
  StreamSubscription<Map<String, BleSessionProximity>>? _proximitySub;
  final _proximityMonitor = BleProximityMonitor.instance;

  @override
  void initState() {
    super.initState();
    _load();
    _connectSocket();
    _proximitySub = _proximityMonitor.stream.listen(_onProximityUpdate);
    unreadCountNotifier.refresh();
    _sessionRefreshTimer =
        Timer.periodic(const Duration(seconds: 25), (_) => _fetchSessionsFromApi());
  }

  @override
  void dispose() {
    _sessionRefreshTimer?.cancel();
    _proximitySub?.cancel();
    _proximityMonitor.stop();
    _socket?.disconnect();
    _socket?.dispose();
    super.dispose();
  }

  void _onProximityUpdate(Map<String, BleSessionProximity> states) {
    if (!mounted) return;
    setState(() {
      _proximity = states;
      _activeSessions = _sessionsInBluetoothRange();
    });
  }

  List<Map<String, dynamic>> _sessionsInBluetoothRange() {
    return _apiSessions.where((s) {
      final id = (s['id'] ?? s['session_id'] ?? '').toString();
      return _proximity[id]?.visibleOnDashboard == true;
    }).toList();
  }

  BleSessionProximity? _proximityFor(Map<String, dynamic> session) {
    final id = (session['id'] ?? session['session_id'] ?? '').toString();
    return _proximity[id];
  }

  /// Reload stats, modules, and live sessions (e.g. after marking attendance).
  Future<void> _refreshDashboard() async {
    if (!mounted) return;
    await _load();
  }

  Future<void> _load() async {
    Map<String, dynamic>? stats;
    var registered = _faceRegistered;
    var joinedModules = <Map<String, dynamic>>[];

    try {
      stats = await AttendanceService().getStats();
    } catch (_) {}

    try {
      registered = await FaceRegistrationService().isFaceRegistered();
    } catch (_) {}

    try {
      joinedModules = await CatalogService().getStudentModules();
    } catch (_) {}

    if (mounted) {
      setState(() {
        if (stats != null) _stats = stats;
        _faceRegistered = registered;
        _joinedModules = joinedModules;
      });
    }
    await _fetchSessionsFromApi();
  }

  void _connectSocket() {
    _socket = io.io(ApiConfig.socketOrigin, io.OptionBuilder().setTransports(['websocket']).build());
    _socket!.connect();
    _socket!.on('session:started', (dynamic raw) {
      _fetchSessionsFromApi();
      unreadCountNotifier.refresh();
      if (raw is Map) {
        final payload = Map<String, dynamic>.from(raw);
        NotificationService.instance.showSessionStartedFromPayload(payload);
      }
    });
    _socket!.on('session:closed', (_) => _fetchSessionsFromApi());
    _socket!.on('attendance:updated', (_) => _refreshDashboard());
    _socket!.on('attendance:marked', (_) => _refreshDashboard());
    _socket!.on('attendance:record-updated', (_) => _refreshDashboard());
    _joinStudentRoom();
  }

  void _joinStudentRoom() {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user?.id != null) {
      _socket?.emit('join:student', user!.id);
    }
  }

  void _joinClassRooms() {
    _joinStudentRoom();
    for (final id in _enrolledClassIds) {
      _socket?.emit('join:class', id);
    }
  }

  Future<void> _fetchSessionsFromApi() async {
    if (!mounted) return;
    setState(() => _loadingSessions = true);
    try {
      final result = await AttendanceService().getStudentActiveSessions();
      final all = result.sessions;
      final ids = all
          .map((s) => (s['id'] ?? s['session_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toList();

      await _proximityMonitor.setSessionIds(ids);

      if (mounted) {
        setState(() {
          _apiSessionCount = all.length;
          _apiSessions = all;
          _activeSessions = _sessionsInBluetoothRange();
          _enrolledClassIds = result.enrolledClassIds;
          _loadingSessions = false;
        });
        _joinClassRooms();
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() => _activeSessions = []);
        final msg = ApiClient.messageFromDio(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.response?.statusCode == 404
                  ? 'Could not load sessions. Restart the backend (npm start in backend/).'
                  : 'Could not load sessions: $msg',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _activeSessions = []);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not load sessions: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted && _loadingSessions) setState(() => _loadingSessions = false);
    }
  }

  Future<void> _markAttendance(Map<String, dynamic> session) async {
    final registered = await FaceRegistrationService().isFaceRegistered();
    if (mounted) setState(() => _faceRegistered = registered);
    if (!registered) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Register your face first (smile, up, down, right, left)'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (session['already_marked'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You already marked attendance for this session')));
      return;
    }

    await _proximityMonitor.stop();
    final ok = await context.push<bool>(
      '/live-auth',
      extra: {
        'sessionId': session['id'],
        'sessionToken': session['session_token'],
        'session': session,
      },
    );
    if (!mounted) return;
    if (ok == true) await _refreshDashboard();
    else await _fetchSessionsFromApi();
  }

  Future<void> _showJoinModuleSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _JoinModuleSheet(onJoined: _load),
    );
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

  String _moduleKey(Map<String, dynamic> module) {
    final raw = module['module_id'] ??
        module['moduleId'] ??
        module['subject_id'] ??
        module['subjectId'] ??
        module['class_id'] ??
        module['classId'] ??
        module['code'] ??
        module['id'] ??
        module['name'] ??
        module['moduleName'] ??
        module['subject_name'] ??
        module['subjectName'] ??
        '';
    return raw.toString().trim().toLowerCase();
  }

  List<Map<String, dynamic>> _moduleStatsFromAttendance() {
    final candidates = [_stats?['modules'], _stats?['moduleStats'], _stats?['subjects'], _stats?['classes']];
    for (final item in candidates) {
      if (item is List) return item.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }
    return <Map<String, dynamic>>[];
  }

  List<Map<String, dynamic>> _modules() {
    final statModules = _moduleStatsFromAttendance();
    final statsByKey = <String, Map<String, dynamic>>{};
    for (final module in statModules) {
      final key = _moduleKey(module);
      if (key.isNotEmpty) statsByKey[key] = module;
    }

    if (_joinedModules.isNotEmpty) {
      return _joinedModules.map((module) {
        final key = _moduleKey(module);
        final stat = statsByKey[key];
        return stat == null ? module : <String, dynamic>{...module, ...stat};
      }).toList();
    }

    // Do not create an "Overall Attendance" pseudo-module. The dashboard should
    // show only actual joined modules with their own progress bars.
    return statModules;
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).valueOrNull;
    return EnterpriseScaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        actions: [
          ValueListenableBuilder<int>(
            valueListenable: unreadCountNotifier,
            builder: (context, count, _) => Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  tooltip: 'Notifications',
                  icon: const Icon(Icons.notifications_none_rounded),
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const NotificationScreen(),
                    ));
                  },
                ),
                if (count > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        count > 99 ? '99+' : '$count',
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
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
      body: enterpriseMetricsScope(
        context,
        child: RefreshIndicator(
        onRefresh: _refreshDashboard,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, enterpriseContentTopInset(context), 16, 110),
          children: [
            _StudentHero(
              name: user?.fullName ?? 'Student',
              subtitle: user?.studentId ?? user?.email ?? '',
              greeting: _greeting(),
              initial: _initial(user?.fullName),
              faceRegistered: _faceRegistered,
              onFaceRegister: () async {
                await context.push('/face-register');
                if (mounted) await _load();
              },
            ).animate().fadeIn(duration: 450.ms).slideY(begin: 0.04),
            const SizedBox(height: 18),
            if (_activeSessions.isNotEmpty)
              ..._activeSessions.map((session) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _LiveSessionBanner(
                      session: session,
                      proximity: _proximityFor(session),
                      loading: _loadingSessions,
                      onMark: () => _markAttendance(session),
                    ),
                  )),
            if (_apiSessionCount > 0 && _activeSessions.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: GlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.bluetooth_searching, color: Color(0xFF3B82F6)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _loadingSessions
                              ? 'Scanning for teacher Bluetooth (within ${AppConstants.bleMaxDistanceMeters.toInt()} m)...'
                              : _proximity.values.any((p) => p.band == BleProximityBand.weak)
                                  ? 'You are almost in range. Move a little closer (within ${AppConstants.bleMaxDistanceMeters.toInt()} m of your teacher).'
                                  : 'You are outside range. A session is live — move closer to your teacher (within ${AppConstants.bleMaxDistanceMeters.toInt()} m) with Bluetooth on to mark attendance.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      if (_loadingSessions)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                ),
              ),
            if (_activeSessions.isEmpty && _apiSessionCount == 0)
              GlassCard(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.sensors_off_outlined, color: Theme.of(context).colorScheme.outline),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _loadingSessions
                            ? 'Checking for live sessions...'
                            : 'No live session currently active.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    if (_loadingSessions)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
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
              ..._modules().map(
                (m) => _ModuleAttendanceCard(
                  data: m,
                  onTap: () async {
                    await context.push('/module-details', extra: m);
                    if (mounted) await _refreshDashboard();
                  },
                ).animate().fadeIn(duration: 400.ms),
              ),
            const SizedBox(height: 24),
            const SectionTitle(title: 'Quick Actions'),
            const SizedBox(height: 14),
            MetricsQuadGrid(
              children: [
                MetricTile(label: 'Present', value: '${_stats?['present'] ?? 0}', icon: Icons.check_circle_outline, color: const Color(0xFF10B981)),
                MetricTile(label: 'Absent/Rejected', value: '${_stats?['absent'] ?? _stats?['rejected'] ?? 0}', icon: Icons.cancel_outlined, color: const Color(0xFFEF4444)),
                MetricTile(label: 'Medical Leave', value: '${_stats?['medicalLeave'] ?? _stats?['medical_leave'] ?? 0}', icon: Icons.medical_services_outlined, color: const Color(0xFF3B82F6)),
                MetricTile(label: 'Total Records', value: '${_stats?['total'] ?? 0}', icon: Icons.list_alt_outlined),
              ],
            ),
            const SizedBox(height: 16),
            AppButton(
              label: 'History',
              icon: Icons.history,
              outlined: true,
              onPressed: () => context.push('/history'),
            ),
          ],
        ),
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
  final bool faceRegistered;
  final VoidCallback onFaceRegister;

  const _StudentHero({
    required this.name,
    required this.subtitle,
    required this.greeting,
    required this.initial,
    required this.faceRegistered,
    required this.onFaceRegister,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassCard(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: scheme.primary.withValues(alpha: 0.15),
                child: Text(
                  initial,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    color: scheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      greeting,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.72),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      name.trim().isEmpty ? 'Student' : name.trim(),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                      softWrap: true,
                    ),
                    if (subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        subtitle.trim(),
                        style: Theme.of(context).textTheme.bodySmall,
                        softWrap: true,
                      ),
                    ],
                  ],
                ),
              ),
              if (faceRegistered) ...[
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.verified_user,
                    color: scheme.primary,
                    size: 28,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (!faceRegistered) ...[
          const SizedBox(height: 14),
          GlassCard(
            padding: const EdgeInsets.all(20),
            color: scheme.primary.withValues(alpha: 0.08),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    AppBrandLogo.inline(size: 44),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Register your face to mark attendance',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Complete smile, up, down, right, and left once. Only your face can mark attendance later.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                AppButton(
                  label: 'Register Face Now',
                  icon: Icons.camera_alt_outlined,
                  onPressed: onFaceRegister,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _LiveSessionBanner extends StatelessWidget {
  final Map<String, dynamic> session;
  final BleSessionProximity? proximity;
  final bool loading;
  final VoidCallback onMark;

  const _LiveSessionBanner({
    required this.session,
    this.proximity,
    required this.loading,
    required this.onMark,
  });

  DateTime _endsAt() {
    final raw = session['ends_at'] ?? session['endsAt'];
    if (raw is String) return DateTime.tryParse(raw) ?? DateTime.now().add(const Duration(minutes: 5));
    return DateTime.now().add(const Duration(minutes: 5));
  }

  @override
  Widget build(BuildContext context) {
    final marked = session['already_marked'] == true;
    final subject = (session['subject_name'] ?? session['subjectName'] ?? 'Active Class').toString();
    final teacher = (session['teacher_name'] ?? session['teacherName'] ?? session['teacher'] ?? 'Teacher').toString();
    final ready = proximity?.canMarkAttendance ?? false;
    final proximityLabel = proximity?.bandLabel ??
        'Within ${AppConstants.bleMaxDistanceMeters.toInt()} m';
    final distText = proximity?.estimatedMeters != null
        ? ' · ≈${proximity!.estimatedMeters!.toStringAsFixed(0)} m'
        : '';

    return GlassCard(
      padding: const EdgeInsets.all(18),
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
      border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.30)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(width: 12, height: 12, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)).animate(onPlay: (c) => c.repeat()).scale(begin: const Offset(0.85, 0.85), end: const Offset(1.25, 1.25), duration: 850.ms).fadeIn(),
              Text('Attendance Session Active', style: Theme.of(context).textTheme.titleMedium),
              SessionTimer(endsAt: _endsAt()),
            ],
          ),
          const SizedBox(height: 10),
          Text(subject, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900), maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(teacher, style: Theme.of(context).textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusPill(
                label: marked
                    ? 'Already Marked'
                    : '$proximityLabel$distText',
                icon: marked
                    ? Icons.check_circle
                    : ready
                        ? Icons.bluetooth_connected
                        : Icons.bluetooth_searching,
                color: marked
                    ? const Color(0xFF10B981)
                    : ready
                        ? const Color(0xFF10B981)
                        : const Color(0xFF3B82F6),
              ),
              ElevatedButton.icon(
                onPressed: marked || loading || !ready ? null : onMark,
                icon: ClipOval(
                  child: Image.asset(
                    AppConstants.brandIconAsset,
                    width: 22,
                    height: 22,
                    fit: BoxFit.cover,
                  ),
                ),
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
                      Text(name.toString(), style: Theme.of(context).textTheme.titleLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(teacher.toString(), style: Theme.of(context).textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
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
