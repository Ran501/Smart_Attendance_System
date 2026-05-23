import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/notification_service.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  List<Map<String, dynamic>> _notifications = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await NotificationService.instance.fetchNotifications();
    if (mounted) setState(() { _notifications = items; _loading = false; });
    await NotificationService.instance.markAllRead();
    unreadCountNotifier.value = 0;
  }

  String _formatTime(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final now = DateTime.now();
    if (now.difference(dt).inDays == 0) return DateFormat('HH:mm').format(dt);
    if (now.difference(dt).inDays < 7) return DateFormat('EEE HH:mm').format(dt);
    return DateFormat('dd MMM').format(dt);
  }

  Color _colorForType(String? type) {
    if (type == null) return Colors.blue;
    if (type.contains('SESSION')) return Colors.green.shade700;
    if (type.contains('DANGER')) return Colors.red.shade600;
    if (type.contains('WARNING')) return Colors.orange.shade700;
    return Colors.blue.shade700;
  }

  IconData _iconForType(String? type) {
    if (type == null) return Icons.notifications;
    if (type.contains('SESSION')) return Icons.sensors_rounded;
    if (type.contains('DANGER')) return Icons.warning_rounded;
    if (type.contains('WARNING')) return Icons.info_rounded;
    return Icons.notifications;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.notifications_none, size: 64, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('No notifications yet', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _notifications.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final n = _notifications[i];
                      final type = n['type'] as String?;
                      final isRead = n['is_read'] == true;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _colorForType(type).withValues(alpha:0.15),
                          child: Icon(_iconForType(type), color: _colorForType(type), size: 22),
                        ),
                        title: Text(
                          n['title'] as String? ?? '',
                          style: TextStyle(
                            fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          n['body'] as String? ?? '',
                          style: const TextStyle(fontSize: 13),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                          _formatTime(n['created_at'] as String?),
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                        tileColor: isRead ? null : _colorForType(type).withValues(alpha:0.04),
                      );
                    },
                  ),
                ),
    );
  }
}
