import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../../../../core/config/api_config.dart';
import '../../../../models/attendance_record_model.dart';
import '../../../../services/attendance_service.dart';
import '../../../../services/auth_service.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  State<AttendanceHistoryScreen> createState() => _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  List<AttendanceRecordModel> _records = [];
  io.Socket? _socket;

  @override
  void initState() {
    super.initState();
    _load();
    _connectSocket();
  }

  @override
  void dispose() {
    _socket?.disconnect();
    _socket?.dispose();
    super.dispose();
  }

  Future<void> _connectSocket() async {
    _socket = io.io(ApiConfig.socketOrigin, io.OptionBuilder().setTransports(['websocket']).build());
    _socket!.connect();
    final user = await AuthService().restoreSession();
    if (user?.id != null) {
      _socket!.emit('join:student', user!.id);
    }
    _socket!.on('attendance:updated', (_) => _load());
    _socket!.on('attendance:marked', (_) => _load());
    _socket!.on('attendance:record-updated', (_) => _load());
  }

  Future<void> _load() async {
    try {
      final records = await AttendanceService().getHistory();
      if (mounted) setState(() => _records = records);
    } catch (_) {}
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'PRESENT':
        return Colors.green;
      case 'LATE':
        return Colors.orange;
      case 'REJECTED':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance History')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _records.isEmpty
            ? const Center(child: Text('No attendance records'))
            : ListView.builder(
                itemCount: _records.length,
                itemBuilder: (_, i) {
                  final r = _records[i];
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _statusColor(r.status),
                        child: Text(r.status[0]),
                      ),
                      title: Text(r.subjectName ?? r.sessionId),
                      subtitle: Text(
                        '${r.className ?? ''}\n${DateFormat.yMMMd().add_jm().format(r.markedAt)}',
                      ),
                      trailing: r.matchConfidence != null
                          ? Text('${(r.matchConfidence! * 100).toStringAsFixed(0)}%')
                          : null,
                    ),
                  );
                },
              ),
      ),
    );
  }
}
