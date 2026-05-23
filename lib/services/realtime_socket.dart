import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../core/config/api_config.dart';

typedef RealtimePayloadCallback = void Function(dynamic payload);

/// Socket.IO helper for live session and attendance updates (no manual refresh).
class RealtimeAttendanceSocket {
  io.Socket? _socket;

  void connect({
    Iterable<String> classIds = const [],
    String? sessionId,
    String? studentUserId,
    required VoidCallback onDataChanged,
    RealtimePayloadCallback? onSessionStarted,
    RealtimePayloadCallback? onSessionClosed,
  }) {
    disconnect();

    _socket = io.io(
      ApiConfig.socketOrigin,
      io.OptionBuilder().setTransports(['websocket']).build(),
    );
    _socket!.connect();

    for (final id in classIds) {
      final trimmed = id.trim();
      if (trimmed.isNotEmpty) {
        _socket!.emit('join:class', trimmed);
      }
    }

    final sid = sessionId?.trim();
    if (sid != null && sid.isNotEmpty) {
      _socket!.emit('join:session', sid);
    }

    final uid = studentUserId?.trim();
    if (uid != null && uid.isNotEmpty) {
      _socket!.emit('join:student', uid);
    }

    void refresh([dynamic payload]) => onDataChanged();

    _socket!
      ..on('session:started', (dynamic raw) {
        onDataChanged();
        onSessionStarted?.call(raw);
      })
      ..on('session:closed', (dynamic raw) {
        onDataChanged();
        onSessionClosed?.call(raw);
      })
      ..on('attendance:updated', refresh)
      ..on('attendance:marked', refresh)
      ..on('attendance:record-updated', refresh);
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }
}
