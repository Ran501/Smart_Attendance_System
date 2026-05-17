import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../../../../core/constants/app_constants.dart';
import '../../../../services/attendance_service.dart';
import '../../../../services/geo_fence_service.dart';
import '../../../../services/report_service.dart';
import '../../../../widgets/session_timer.dart';

class AttendanceSessionScreen extends StatefulWidget {
  final String sessionId;

  const AttendanceSessionScreen({super.key, required this.sessionId});

  @override
  State<AttendanceSessionScreen> createState() => _AttendanceSessionScreenState();
}

class _AttendanceSessionScreenState extends State<AttendanceSessionScreen> {
  Map<String, dynamic>? _session;
  List<dynamic> _attendance = [];
  String? _qrPayload;
  io.Socket? _socket;
  Timer? _locationTimer;
  final _geo = GeoFenceService();

  @override
  void initState() {
    super.initState();
    _load();
    _connectSocket();
    _startLocationRefresh();
  }

  void _startLocationRefresh() {
    _refreshTeacherLocation();
    _locationTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _refreshTeacherLocation(),
    );
  }

  Future<void> _refreshTeacherLocation() async {
    try {
      final pos = await _geo.getBestPosition(maxSamples: 2);
      if (pos == null) return;
      await AttendanceService().updateSessionLocation(
        sessionId: widget.sessionId,
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracy: pos.accuracy,
      );
    } catch (_) {}
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final extra = GoRouterState.of(context).extra;
    if (extra != null && _qrPayload == null) {
      if (extra is Map<String, dynamic>) {
        _session = extra;
        _qrPayload = extra['qrPayload'] as String? ?? extra['qr_payload'] as String?;
      } else {
        try {
          final dynamic e = extra;
          _qrPayload = e.qrPayload as String?;
          _session = {'ends_at': (e.endsAt as DateTime).toIso8601String()};
        } catch (_) {}
      }
    }
  }

  Future<void> _load() async {
    try {
      final api = AttendanceService();
      final records = await api.getSessionAttendance(widget.sessionId);
      if (mounted) setState(() => _attendance = records);
    } catch (_) {}
  }

  void _connectSocket() {
    final baseUrl = AppConstants.apiBaseUrl.replaceAll('/api/v1', '');
    _socket = io.io(baseUrl, io.OptionBuilder().setTransports(['websocket']).build());
    _socket!.connect();
    _socket!.emit('join:session', widget.sessionId);
    _socket!.on('attendance:marked', (_) => _load());
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _socket?.disconnect();
    _socket?.dispose();
    super.dispose();
  }

  Future<void> _export(String type) async {
    final report = ReportService();
    final records = _attendance.cast<Map<String, dynamic>>();
    File? file;
    switch (type) {
      case 'pdf':
        file = await report.exportPdf(
          sessionId: widget.sessionId,
          session: _session ?? {'class_id': widget.sessionId},
          records: records,
        );
      case 'csv':
        file = await report.exportCsv(sessionId: widget.sessionId, records: records);
      case 'excel':
        file = await report.exportExcel(sessionId: widget.sessionId, records: records);
    }
    if (mounted && file != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported to ${file.path}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final endsAt = _session?['ends_at'] != null
        ? DateTime.parse(_session!['ends_at'] as String)
        : DateTime.now().add(const Duration(minutes: 5));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.sessionId),
        actions: [
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
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(child: SessionTimer(endsAt: endsAt, onExpired: _load)),
            const SizedBox(height: 24),
            if (_qrPayload != null)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.white,
                  child: QrImageView(
                    data: _qrPayload!,
                    version: QrVersions.auto,
                    size: 220,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              'Keep this screen open — your location refreshes every 15s so nearby students can mark attendance.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            Text('Live Attendance (${_attendance.length})',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            ..._attendance.map((r) {
              final m = r as Map<String, dynamic>;
              return Card(
                child: ListTile(
                  leading: Icon(
                    m['status'] == 'PRESENT' ? Icons.check_circle : Icons.cancel,
                    color: m['status'] == 'PRESENT' ? Colors.green : Colors.red,
                  ),
                  title: Text(m['full_name'] as String? ?? ''),
                  subtitle: Text(
                    '${m['status']} • ${((m['match_confidence'] as num? ?? 0) * 100).toStringAsFixed(0)}%',
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
