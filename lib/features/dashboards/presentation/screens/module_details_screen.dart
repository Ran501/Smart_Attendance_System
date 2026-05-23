import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../services/attendance_service.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/catalog_service.dart';
import '../../../../services/notification_service.dart';
import '../../../../services/notification_service.dart';
import '../../../../services/realtime_socket.dart';
import '../../../../widgets/enterprise_shell.dart';

class ModuleDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> module;

  const ModuleDetailsScreen({super.key, required this.module});

  @override
  State<ModuleDetailsScreen> createState() => _ModuleDetailsScreenState();
}

class _ModuleDetailsScreenState extends State<ModuleDetailsScreen> {
  final _attendanceService = AttendanceService();
  List<Map<String, dynamic>> _records = [];
  List<Map<String, dynamic>> _sessions = [];
  Map<String, dynamic> _moduleStats = {};
  bool _loading = false;
  String? _error;
  final _realtime = RealtimeAttendanceSocket();
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _connectRealtime();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && !_loading) _loadQuiet();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _realtime.disconnect();
    super.dispose();
  }

  String? get _classIdForSocket {
    final raw = module['class_id'] ??
        module['classId'] ??
        module['module_id'] ??
        module['moduleId'] ??
        module['subject_id'] ??
        module['subjectId'];
    final id = raw?.toString().trim();
    return (id == null || id.isEmpty) ? null : id;
  }

  Future<void> _connectRealtime() async {
    final classId = _classIdForSocket;
    final user = await AuthService().restoreSession();
    _realtime.connect(
      classIds: classId != null ? [classId] : const [],
      studentUserId: user?.id,
      onDataChanged: () async {
        if (mounted) await _loadQuiet();
        await NotificationService.instance.refreshUnreadBell();
      },
      onSessionStarted: (raw) async {
        if (raw is Map) {
          await NotificationService.instance.showLiveSessionFromPayloadOnce(
            Map<String, dynamic>.from(raw),
          );
        }
        await NotificationService.instance.refreshUnreadBell();
      },
      onSessionClosed: (_) {
        if (mounted) _loadQuiet();
      },
    );
  }

  Future<void> _refreshModuleStats() async {
    try {
      final modules = await CatalogService().getStudentModules();
      final id = _moduleId.trim().toLowerCase();
      for (final row in modules) {
        final keys = [
          row['subject_id'],
          row['subjectId'],
          row['module_id'],
          row['moduleId'],
          row['id'],
          row['code'],
        ].whereType<Object>().map((e) => e.toString().trim().toLowerCase());
        if (keys.contains(id)) {
          if (mounted) setState(() => _moduleStats = row);
          return;
        }
      }
    } catch (_) {}
  }

  Future<void> _loadQuiet() async {
    try {
      var records = <Map<String, dynamic>>[];
      var sessions = <Map<String, dynamic>>[];
      if (_moduleId.trim().isNotEmpty) {
        final results = await Future.wait<dynamic>([
          _attendanceService.getStudentModuleRecords(moduleId: _moduleId),
          _attendanceService.getStudentModuleSessions(moduleId: _moduleId),
          CatalogService().getStudentModules(),
        ]);
        records = List<Map<String, dynamic>>.from(results[0] as List);
        sessions = List<Map<String, dynamic>>.from(results[1] as List);
        final modules = List<Map<String, dynamic>>.from(results[2] as List);
        final id = _moduleId.trim().toLowerCase();
        for (final row in modules) {
          final keys = [
            row['subject_id'],
            row['subjectId'],
            row['module_id'],
            row['moduleId'],
            row['id'],
            row['code'],
          ].whereType<Object>().map((e) => e.toString().trim().toLowerCase());
          if (keys.contains(id)) {
            _moduleStats = row;
            break;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _records = records;
        _sessions = sessions;
        _error = null;
      });
    } catch (_) {}
  }

  Map<String, dynamic> get module => widget.module;

  String get _moduleId {
    return (module['module_id'] ??
            module['moduleId'] ??
            module['subject_id'] ??
            module['subjectId'] ??
            module['class_id'] ??
            module['classId'] ??
            module['code'] ??
            module['id'] ??
            '')
        .toString();
  }

  String get _moduleName {
    return (module['name'] ??
            module['moduleName'] ??
            module['module_name'] ??
            module['subject_name'] ??
            module['subjectName'] ??
            'Module')
        .toString();
  }

  String get _teacherName {
    return (module['teacher_name'] ?? module['teacherName'] ?? module['teacher'] ?? 'Teacher').toString();
  }

  List<Map<String, dynamic>> _listFrom(dynamic data) {
    if (data is List) return data.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    if (data is Map) {
      for (final key in const ['records', 'attendance', 'history', 'sessions', 'data']) {
        final value = data[key];
        if (value is List) return value.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
      }
    }
    return <Map<String, dynamic>>[];
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      var records = <Map<String, dynamic>>[];
      var sessions = <Map<String, dynamic>>[];

      if (_moduleId.trim().isNotEmpty) {
        final results = await Future.wait<dynamic>([
          _attendanceService.getStudentModuleRecords(moduleId: _moduleId),
          _attendanceService.getStudentModuleSessions(moduleId: _moduleId),
        ]);
        records = List<Map<String, dynamic>>.from(results[0] as List);
        sessions = List<Map<String, dynamic>>.from(results[1] as List);
      }

      if (records.isEmpty) {
        records = _listFrom(module['records'] ?? module['attendance'] ?? module['history']);
      }
      if (sessions.isEmpty) {
        sessions = _listFrom(module['sessions']);
      }

      if (mounted) {
        setState(() {
          _records = records;
          _sessions = sessions;
        });
        await _refreshModuleStats();
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _numValue(Map<String, dynamic> source, List<String> keys, [double fallback = 0]) {
    for (final key in keys) {
      final raw = source[key];
      if (raw is num) return raw.toDouble();
      final parsed = double.tryParse(raw?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return fallback;
  }

  String _statusOf(Map<String, dynamic> record) {
    final raw = (record['status'] ?? record['attendance_status'] ?? record['attendanceStatus'] ?? '')
        .toString()
        .trim()
        .toUpperCase();
    if (raw.isEmpty || raw == 'NULL') return 'ABSENT';
    if (raw == 'MEDICAL' || raw == 'MEDICAL LEAVE' || raw == 'ML') return 'MEDICAL_LEAVE';
    if (raw == 'OFFICIAL' || raw == 'OFFICIAL LEAVE' || raw == 'OL') return 'OFFICIAL_LEAVE';
    return raw;
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'PRESENT':
        return 'Present';
      case 'MEDICAL_LEAVE':
        return 'Medical Leave';
      case 'OFFICIAL_LEAVE':
        return 'Official Leave';
      case 'REJECTED':
        return 'Rejected';
      default:
        return 'Absent';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'PRESENT':
        return const Color(0xFF10B981);
      case 'MEDICAL_LEAVE':
        return const Color(0xFF2563EB);
      case 'OFFICIAL_LEAVE':
        return const Color(0xFF8B5CF6);
      case 'REJECTED':
        return const Color(0xFFF97316);
      default:
        return const Color(0xFFEF4444);
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'PRESENT':
        return Icons.check_circle_outline;
      case 'MEDICAL_LEAVE':
        return Icons.medical_services_outlined;
      case 'OFFICIAL_LEAVE':
        return Icons.verified_outlined;
      case 'REJECTED':
        return Icons.gpp_bad_outlined;
      default:
        return Icons.cancel_outlined;
    }
  }

  int _countStatus(String status) => _records.where((record) => _statusOf(record) == status).length;

  bool get _hasLiveRecords => _records.isNotEmpty;

  Map<String, dynamic> get _statsMap =>
      _moduleStats.isNotEmpty ? <String, dynamic>{...module, ..._moduleStats} : module;

  Set<String> get _uniqueSessionIds {
    return _records
        .map((record) => (record['session_id'] ?? record['sessionId'] ?? record['session'] ?? '').toString())
        .where((id) => id.trim().isNotEmpty)
        .toSet();
  }

  int get _presentCount {
    if (_hasLiveRecords) return _countStatus('PRESENT');
    final fromModule = _numValue(_statsMap, const ['attended', 'present', 'classesAttended'], -1).toInt();
    if (fromModule >= 0) return fromModule;
    return _countStatus('PRESENT');
  }

  int get _medicalCount {
    if (_hasLiveRecords) return _countStatus('MEDICAL_LEAVE');
    final fromModule = _numValue(_statsMap, const ['medical_leave', 'medicalLeave'], -1).toInt();
    if (fromModule >= 0) return fromModule;
    return _countStatus('MEDICAL_LEAVE');
  }

  int get _officialCount {
    if (_hasLiveRecords) return _countStatus('OFFICIAL_LEAVE');
    final fromModule = _numValue(_statsMap, const ['official_leave', 'officialLeave'], -1).toInt();
    if (fromModule >= 0) return fromModule;
    return _countStatus('OFFICIAL_LEAVE');
  }

  int get _absentCount {
    if (_hasLiveRecords) {
      return _records.where((record) {
        final status = _statusOf(record);
        return status == 'ABSENT' || status == 'REJECTED';
      }).length;
    }
    final fromModule = _numValue(_statsMap, const ['absent', 'rejected'], -1).toInt();
    if (fromModule >= 0) return fromModule;
    return _records.where((record) {
      final status = _statusOf(record);
      return status == 'ABSENT' || status == 'REJECTED';
    }).length;
  }

  int get _totalSessions {
    if (_hasLiveRecords && _sessions.isNotEmpty) return _sessions.length;
    if (_hasLiveRecords && _uniqueSessionIds.isNotEmpty) return _uniqueSessionIds.length;
    final fromModule = _numValue(
      _statsMap,
      const ['total_sessions', 'totalSessions', 'session_count', 'sessionCount', 'total', 'classesTotal', 'totalClasses'],
      -1,
    ).toInt();
    if (fromModule >= 0) return fromModule;
    if (_sessions.isNotEmpty) return _sessions.length;
    if (_uniqueSessionIds.isNotEmpty) return _uniqueSessionIds.length;
    return _presentCount + _absentCount + _medicalCount + _officialCount;
  }

  double get _percentage {
    if (_moduleStats.isNotEmpty) {
      final fromStats = _numValue(_statsMap, const ['percentage', 'attendancePercentage', 'attendance_percentage'], -1);
      if (fromStats >= 0) return fromStats;
    }
    if (_hasLiveRecords) {
      final total = _totalSessions;
      if (total <= 0) return 0;
      return (_presentCount / total) * 100;
    }
    final fromModule = _numValue(_statsMap, const ['percentage', 'attendancePercentage', 'attendance_percentage'], -1);
    if (fromModule >= 0) return fromModule;
    final total = _totalSessions;
    if (total <= 0) return 0;
    return (_presentCount / total) * 100;
  }

  int get _maxAllowedAbsences {
    final v = _numValue(_statsMap, const ['maxAllowedAbsences', 'max_allowed_absences'], -1).toInt();
    return v >= 0 ? v : 0;
  }

  int get _absencesRemaining {
    final v = _numValue(_statsMap, const ['absencesRemaining', 'absences_remaining'], -1).toInt();
    return v >= 0 ? v : 0;
  }

  String _dateOf(Map<String, dynamic> record) {
    final raw = record['marked_at'] ??
        record['markedAt'] ??
        record['created_at'] ??
        record['createdAt'] ??
        record['started_at'] ??
        record['startedAt'] ??
        record['date'];
    if (raw == null) return 'Date not recorded';
    final parsed = DateTime.tryParse(raw.toString());
    if (parsed == null) return raw.toString();
    final local = parsed.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final yyyy = local.year.toString();
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$dd/$mm/$yyyy $hh:$min';
  }

  String _sessionIdOf(Map<String, dynamic> source) {
    return (source['session_id'] ?? source['sessionId'] ?? source['id'] ?? 'Session').toString();
  }

  String _subtitleOf(Map<String, dynamic> record) {
    final bits = <String>[
      _dateOf(record),
      if (_sessionIdOf(record) != 'Session') 'Session: ${_sessionIdOf(record)}',
    ];
    final reason = record['reason'] ?? record['reject_reason'] ?? record['rejection_reason'] ?? record['note'];
    if (reason != null && reason.toString().trim().isNotEmpty) bits.add('Note: $reason');
    return bits.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final color = _percentage >= 90
        ? const Color(0xFF10B981)
        : _percentage >= 80
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEF4444);

    return EnterpriseScaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: enterpriseMetricsScope(
        context,
        child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, enterpriseContentTopInset(context), 16, 36),
          children: [
            GlassCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_moduleName, style: Theme.of(context).textTheme.headlineSmall),
                            const SizedBox(height: 5),
                            Text(_teacherName, style: Theme.of(context).textTheme.bodyMedium),
                          ],
                        ),
                      ),
                      AttendanceLiquidGauge(percentage: _percentage, size: 96, compact: true),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: (_percentage / 100).clamp(0.0, 1.0).toDouble(),
                      minHeight: 9,
                      color: color,
                      backgroundColor: color.withValues(alpha: 0.12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      StatusPill(label: 'Total Sessions: $_totalSessions', icon: Icons.event_note_outlined, color: const Color(0xFF1E4ED8)),
                      StatusPill(label: '${_percentage.toStringAsFixed(0)}% Attendance', icon: Icons.trending_up_outlined, color: color),
                      if (_maxAllowedAbsences > 0)
                        StatusPill(
                          label: 'Absences left: $_absencesRemaining/$_maxAllowedAbsences',
                          icon: Icons.event_busy_outlined,
                          color: _absencesRemaining <= 1 ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const SectionTitle(title: 'Quick Actions'),
            const SizedBox(height: 12),
            MetricsQuadGrid(
              children: [
                MetricTile(label: 'Present', value: '$_presentCount', icon: Icons.check_circle_outline, color: const Color(0xFF10B981)),
                MetricTile(label: 'Absent/Rejected', value: '$_absentCount', icon: Icons.cancel_outlined, color: const Color(0xFFEF4444)),
                MetricTile(label: 'Medical Leave', value: '$_medicalCount', icon: Icons.medical_services_outlined, color: const Color(0xFF3B82F6)),
                MetricTile(label: 'Official', value: '$_officialCount', icon: Icons.verified_outlined, color: const Color(0xFF8B5CF6)),
              ],
            ),
            const SizedBox(height: 22),
            SectionTitle(
              title: 'Detailed Attendance Report',
              subtitle: 'Your session-by-session attendance for this module.',
              trailing: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : null,
            ),
            const SizedBox(height: 12),
            if (_error != null)
              GlassCard(
                color: const Color(0xFFEF4444).withValues(alpha: 0.10),
                child: Text('Could not load module report: $_error'),
              )
            else if (_records.isEmpty)
              const GlassCard(
                child: ListTile(
                  leading: Icon(Icons.fact_check_outlined),
                  title: Text('No attendance records yet'),
                  subtitle: Text('Your report will appear here after sessions are marked.'),
                ),
              )
            else
              ..._records.map((record) {
                final status = _statusOf(record);
                final statusColor = _statusColor(status);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GlassCard(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: statusColor.withValues(alpha: 0.12),
                          child: Icon(_statusIcon(status), color: statusColor),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_statusLabel(status), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: statusColor)),
                              const SizedBox(height: 3),
                              Text(_subtitleOf(record), style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            const SizedBox(height: 22),
            SectionTitle(
              title: 'Module Sessions',
              subtitle: _sessions.isEmpty ? 'Total counted sessions are shown above.' : 'All available sessions returned for this module.',
            ),
            const SizedBox(height: 12),
            if (_sessions.isEmpty)
              GlassCard(
                child: ListTile(
                  leading: const Icon(Icons.event_available_outlined),
                  title: Text('$_totalSessions total session${_totalSessions == 1 ? '' : 's'}'),
                  subtitle: const Text('No separate session list was returned by the backend.'),
                ),
              )
            else
              ..._sessions.map((session) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GlassCard(
                      padding: const EdgeInsets.all(14),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.event_note_outlined),
                        title: Text(_sessionIdOf(session)),
                        subtitle: Text(_dateOf(session)),
                      ),
                    ),
                  )),
          ],
        ),
        ),
      ),
    );
  }
}
