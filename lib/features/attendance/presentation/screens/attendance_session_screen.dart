import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../../../../core/config/api_config.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../services/api_client.dart';
import '../../../../services/attendance_service.dart';
import '../../../../services/bluetooth_validation_service.dart';
import '../../../../services/teacher_ble_beacon_service.dart';
import '../../../../services/report_service.dart';
import '../../../../widgets/app_button.dart';
import '../../../../widgets/confirm_dialog.dart';
import '../../../../widgets/enterprise_shell.dart';
import '../../../../widgets/session_timer.dart';

class AttendanceSessionScreen extends StatefulWidget {
  final String sessionId;

  const AttendanceSessionScreen({super.key, required this.sessionId});

  @override
  State<AttendanceSessionScreen> createState() => _AttendanceSessionScreenState();
}

class _AttendanceSessionScreenState extends State<AttendanceSessionScreen> {
  Map<String, dynamic>? _session;
  List<Map<String, dynamic>> _attendance = [];
  io.Socket? _socket;
  bool _beaconActive = false;
  final _updating = <String>{};
  bool _loading = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _load();
    _connectSocket();
    _startBleBeacon();
  }

  Future<void> _startBleBeacon() async {
    final result = await TeacherBleBeaconService.instance.start(widget.sessionId);
    if (!mounted) return;
    setState(() => _beaconActive = result.success);
    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 8),
          action: result.openSettings
              ? SnackBarAction(
                  label: 'Settings',
                  onPressed: () => TeacherBleBeaconService.instance.openAppSettings(),
                )
              : null,
        ),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final extra = GoRouterState.of(context).extra;
    if (extra != null && _session == null) {
      if (extra is Map<String, dynamic>) {
        _session = extra;
      } else {
        try {
          final dynamic e = extra;
          _session = {
            'id': e.id,
            'subject_name': e.subjectName,
            'class_name': e.className,
            'ends_at': (e.endsAt as DateTime).toIso8601String(),
          };
        } catch (_) {}
      }
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final records = await AttendanceService().getSessionRoster(widget.sessionId);
      if (mounted) setState(() => _attendance = records);
    } catch (_) {
      try {
        final records = await AttendanceService().getSessionAttendance(widget.sessionId);
        if (mounted) {
          setState(() {
            _attendance = records.map((e) => (e as Map).cast<String, dynamic>()).toList();
          });
        }
      } catch (e) {
        if (mounted) {
          final msg = e is DioException
              ? ApiClient.messageFromDio(e)
              : e.toString().replaceFirst('Exception: ', '');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not load session attendance: $msg'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _connectSocket() {
    _socket = io.io(ApiConfig.socketOrigin, io.OptionBuilder().setTransports(['websocket']).build());
    _socket!.connect();
    _socket!.emit('join:session', widget.sessionId);
    _socket!.on('attendance:marked', (_) => _load());
    _socket!.on('attendance:updated', (_) => _load());
    _socket!.on('attendance:record-updated', (_) => _load());
    _socket!.on('session:closed', (_) => _load());
  }

  @override
  void dispose() {
    TeacherBleBeaconService.instance.stop();
    _socket?.disconnect();
    _socket?.dispose();
    super.dispose();
  }

  Future<void> _export(String type) async {
    final report = ReportService();
    final records = _attendance;
    try {
      ReportExportResult result;
      switch (type) {
        case 'pdf':
          result = await report.exportPdf(
            sessionId: widget.sessionId,
            session: _session ?? {'class_id': widget.sessionId},
            records: records,
          );
          break;
        case 'csv':
          result = await report.exportCsv(
            sessionId: widget.sessionId,
            records: records,
          );
          break;
        case 'excel':
          result = await report.exportExcel(
            sessionId: widget.sessionId,
            records: records,
          );
          break;
        default:
          return;
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saved to ${result.displayPath}\n'
            'Files app → Downloads → FacePass folder',
          ),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'OK',
            onPressed: () {},
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  DateTime _endsAt() {
    final raw = _session?['ends_at'] ?? _session?['endsAt'];
    if (raw is String) return DateTime.tryParse(raw) ?? DateTime.now().add(const Duration(minutes: 5));
    return DateTime.now().add(const Duration(minutes: 5));
  }

  int _sessionUnits() {
    final raw = _session?['session_units'] ??
        _session?['sessionUnits'] ??
        _session?['period_count'] ??
        _session?['periodCount'] ??
        _session?['block_periods'] ??
        _session?['blockPeriods'];
    if (raw is num) return raw.toInt().clamp(1, 3).toInt();
    final parsed = int.tryParse(raw?.toString() ?? '');
    return (parsed ?? 1).clamp(1, 3).toInt();
  }

  String _statusOf(Map<String, dynamic> record) {
    final raw = (record['status'] ?? record['attendance_status'] ?? record['attendanceStatus'] ?? '').toString().trim().toUpperCase();
    if (raw.isEmpty || raw == 'NULL') return 'ABSENT';
    if (raw == 'MEDICAL' || raw == 'MEDICAL LEAVE' || raw == 'ML') return 'MEDICAL_LEAVE';
    if (raw == 'OFFICIAL' || raw == 'OFFICIAL LEAVE' || raw == 'OL') return 'OFFICIAL_LEAVE';
    return raw;
  }

  String _labelOf(String status) {
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

  Color _colorOf(String status) {
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

  IconData _iconOf(String status) {
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

  int _count(String status) => _attendance.where((r) => _statusOf(r) == status).length;
  int get _presentCount => _count('PRESENT');
  int get _absentCount => _attendance.where((r) => _statusOf(r) == 'ABSENT' || _statusOf(r) == '').length;
  int get _medicalCount => _count('MEDICAL_LEAVE');
  int get _officialCount => _count('OFFICIAL_LEAVE');
  int get _rejectedCount => _count('REJECTED');

  String _studentName(Map<String, dynamic> m) {
    return (m['full_name'] ??
            m['student_name'] ??
            m['studentName'] ??
            m['name'] ??
            m['user_name'] ??
            m['email'] ??
            'Student')
        .toString();
  }

  String? _recordId(Map<String, dynamic> m) {
    return (m['record_id'] ?? m['recordId'] ?? m['attendance_id'] ?? m['attendanceId'] ?? m['id'])?.toString();
  }

  String? _studentId(Map<String, dynamic> m) {
    return (m['user_id'] ?? m['userId'] ?? m['student_uuid'] ?? m['student_id'] ?? m['studentId'])?.toString();
  }

  String _recordKey(Map<String, dynamic> m) => _recordId(m) ?? _studentId(m) ?? _studentName(m);

  String _confidenceLabel(Map<String, dynamic> m) {
    final raw = m['match_confidence'] ?? m['face_confidence'] ?? m['confidence'];
    if (raw is! num) return 'Face confidence not recorded';
    final value = raw <= 1 ? raw * 100 : raw;
    return 'Face confidence ${value.toStringAsFixed(0)}%';
  }

  void _applyLocalStatus(Map<String, dynamic> record, String status) {
    final idx = _attendance.indexWhere((r) => _recordKey(r) == _recordKey(record));
    if (idx < 0) return;
    final updated = Map<String, dynamic>.from(_attendance[idx]);
    updated['status'] = status;
    updated['attendance_status'] = status;
    updated['attendanceStatus'] = status;
    _attendance[idx] = updated;
  }

  Future<void> _endSessionEarly() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'End session early?',
      message:
          'Students will no longer be able to mark attendance for this session. You can start a new session later.',
      confirmLabel: 'End session',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _closing = true);
    try {
      await AttendanceService().closeSession(widget.sessionId);
      await TeacherBleBeaconService.instance.stop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session ended')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not end session: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  Future<void> _changeStatus(Map<String, dynamic> record, String status) async {
    final key = _recordKey(record);
    setState(() => _updating.add(key));
    try {
      await AttendanceService().updateAttendanceStatus(
        sessionId: widget.sessionId,
        status: status,
        recordId: _recordId(record),
        studentId: _studentId(record),
      );
      if (mounted) {
        setState(() => _applyLocalStatus(record, status));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_studentName(record)} marked as ${_labelOf(status)}')),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update record: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _updating.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) {
    final subject = _session?['subject_name'] ?? _session?['subjectName'] ?? 'Live Session';
    final className = _session?['class_name'] ?? _session?['className'] ?? _session?['class_id'] ?? 'Class';
    final beaconName = BluetoothValidationService.beaconName(widget.sessionId);

    return EnterpriseScaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          PopupMenuButton<String>(
            onSelected: _export,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pdf', child: Text('Export PDF')),
              PopupMenuItem(value: 'csv', child: Text('Export CSV')),
              PopupMenuItem(value: 'excel', child: Text('Export Excel')),
            ],
          ),
        ],
      ),
      body: enterpriseMetricsScope(
        context,
        child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, enterpriseContentTopInset(context), 16, 32),
          children: [
            GlassCard(
              padding: const EdgeInsets.all(20),
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const StatusPill(label: 'SESSION', icon: Icons.fiber_manual_record, color: Color(0xFFEF4444)),
                      const Spacer(),
                      SessionTimer(endsAt: _endsAt(), onExpired: _load),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(subject.toString(), style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 4),
                  Text('$className • Session ID: ${widget.sessionId}', style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 10),
                  StatusPill(label: 'Counts as ${_sessionUnits()} session${_sessionUnits() == 1 ? '' : 's'}', icon: Icons.calculate_outlined, color: const Color(0xFF8B5CF6)),
                  const SizedBox(height: 14),
                  AppButton(
                    label: 'End session now',
                    icon: Icons.stop_circle_outlined,
                    outlined: true,
                    loading: _closing,
                    onPressed: _closing ? null : _endSessionEarly,
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 450.ms).slideY(begin: 0.04),
            const SizedBox(height: 18),
            const SectionTitle(title: 'Session Overview'),
            const SizedBox(height: 12),
            MetricsQuadGrid(
              children: [
                MetricTile(label: 'Present', value: '$_presentCount', icon: Icons.check_circle_outline, color: const Color(0xFF10B981)),
                MetricTile(label: 'Absent', value: '$_absentCount', icon: Icons.cancel_outlined, color: const Color(0xFFEF4444)),
                MetricTile(label: 'Medical', value: '$_medicalCount', icon: Icons.medical_services_outlined, color: const Color(0xFF3B82F6)),
                MetricTile(label: 'Official', value: '$_officialCount', icon: Icons.verified_outlined, color: const Color(0xFF8B5CF6)),
              ],
            ),
            const SizedBox(height: 18),
            GlassCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.bluetooth_connected, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 10),
                      Expanded(child: Text('Bluetooth Proximity Beacon', style: Theme.of(context).textTheme.titleMedium)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _beaconActive
                        ? 'Broadcasting now — students must be within ${AppConstants.bleMaxDistanceMeters.toInt()} m of your phone to mark attendance.'
                        : 'Beacon not active. Turn on Bluetooth and tap refresh, or reopen this session.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  SelectableText(beaconName, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      StatusPill(
                        label: _beaconActive ? 'Beacon ON' : 'Beacon OFF',
                        icon: Icons.bluetooth,
                        color: _beaconActive ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      ),
                      const Spacer(),
                      if (!_beaconActive)
                        FilledButton.icon(
                          onPressed: _startBleBeacon,
                          icon: const Icon(Icons.bluetooth_searching, size: 18),
                          label: const Text('Start beacon'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            SectionTitle(
              title: 'Student Attendance Records',
              subtitle: 'Tap the status menu to change absent to present, medical leave, or official leave.',
              trailing: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : StatusPill(label: '${_attendance.length} Students', icon: Icons.groups_outlined, color: const Color(0xFF1E4ED8)),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                StatusPill(label: 'Present', icon: Icons.check_circle_outline, color: Color(0xFF10B981)),
                StatusPill(label: 'Medical Leave', icon: Icons.medical_services_outlined, color: Color(0xFF2563EB)),
                StatusPill(label: 'Official Leave', icon: Icons.verified_outlined, color: Color(0xFF8B5CF6)),
                StatusPill(label: 'Absent', icon: Icons.cancel_outlined, color: Color(0xFFEF4444)),
              ],
            ),
            const SizedBox(height: 12),
            if (_attendance.isEmpty)
              const GlassCard(child: ListTile(leading: Icon(Icons.person_search_outlined), title: Text('Waiting for students or roster records')))
            else
              ..._attendance.map((m) => _StudentAttendanceTile(
                    record: m,
                    name: _studentName(m),
                    idText: _studentId(m),
                    status: _statusOf(m),
                    confidenceText: _confidenceLabel(m),
                    updating: _updating.contains(_recordKey(m)),
                    labelOf: _labelOf,
                    colorOf: _colorOf,
                    iconOf: _iconOf,
                    onChange: (status) => _changeStatus(m, status),
                  )),
            if (_rejectedCount > 0) ...[
              const SizedBox(height: 10),
              GlassCard(
                padding: const EdgeInsets.all(14),
                color: const Color(0xFFF97316).withValues(alpha: 0.10),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Color(0xFFF97316)),
                    const SizedBox(width: 10),
                    Expanded(child: Text('$_rejectedCount rejected attempts were detected for this session. Review face and Bluetooth proximity before changing records manually.')),
                  ],
                ),
              ),
            ],
          ],
        ),
        ),
      ),
    );
  }
}

class _StudentAttendanceTile extends StatelessWidget {
  final Map<String, dynamic> record;
  final String name;
  final String? idText;
  final String status;
  final String confidenceText;
  final bool updating;
  final String Function(String) labelOf;
  final Color Function(String) colorOf;
  final IconData Function(String) iconOf;
  final ValueChanged<String> onChange;

  const _StudentAttendanceTile({
    required this.record,
    required this.name,
    required this.idText,
    required this.status,
    required this.confidenceText,
    required this.updating,
    required this.labelOf,
    required this.colorOf,
    required this.iconOf,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final color = colorOf(status);
    final markedAt = record['marked_at'] ?? record['markedAt'] ?? record['created_at'];
    final reason = record['reason'] ?? record['reject_reason'] ?? record['note'];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.12),
              child: Icon(iconOf(status), color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (idText != null && idText!.isNotEmpty) 'ID: $idText',
                      confidenceText,
                      if (markedAt != null) 'Time: $markedAt',
                    ].join(' • '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (reason != null && reason.toString().trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('Note: $reason', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color)),
                  ],
                  const SizedBox(height: 8),
                  StatusPill(label: labelOf(status), icon: iconOf(status), color: color),
                ],
              ),
            ),
            const SizedBox(width: 8),
            updating
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : PopupMenuButton<String>(
                    tooltip: 'Change attendance status',
                    icon: const Icon(Icons.more_vert),
                    onSelected: onChange,
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'PRESENT', child: ListTile(leading: Icon(Icons.check_circle_outline), title: Text('Mark Present'))),
                      PopupMenuItem(value: 'ABSENT', child: ListTile(leading: Icon(Icons.cancel_outlined), title: Text('Mark Absent'))),
                      PopupMenuItem(value: 'MEDICAL_LEAVE', child: ListTile(leading: Icon(Icons.medical_services_outlined), title: Text('Medical Leave'))),
                      PopupMenuItem(value: 'OFFICIAL_LEAVE', child: ListTile(leading: Icon(Icons.verified_outlined), title: Text('Official Leave'))),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}
