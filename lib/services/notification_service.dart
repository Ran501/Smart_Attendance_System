import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_client.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _fcm = FirebaseMessaging.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();

  static const _channelId = 'attendance_alerts';
  static const _channelName = 'Attendance Alerts';

  Future<void> initialize() async {
    await _fcm.requestPermission(alert: true, badge: true, sound: true);

    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Live sessions and attendance alerts',
        importance: Importance.high,
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _localNotifications.initialize(initSettings);

    FirebaseMessaging.onMessage.listen((message) async {
      await showLocalNotification(message);
      await unreadCountNotifier.refresh();
    });

    FirebaseMessaging.onMessageOpenedApp.listen((_) => unreadCountNotifier.refresh());

    await syncTokenWithBackend();
    _fcm.onTokenRefresh.listen(_sendTokenToBackend);
  }

  Future<void> showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    final data = message.data;

    final title = notification?.title ?? data['title'] ?? _titleForType(data['type']);
    final body = notification?.body ?? data['body'];
    if (title == null || title.isEmpty || body == null || body.isEmpty) return;

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Live sessions and attendance alerts',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails();

    await _localNotifications.show(
      message.hashCode,
      title,
      body,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  String? _titleForType(String? type) {
    switch (type) {
      case 'SESSION_STARTED':
        return 'Live attendance session';
      default:
        return null;
    }
  }

  /// Call after login / restore session so backend can send pushes while app is closed.
  Future<void> syncTokenWithBackend() async {
    try {
      final token = await _fcm.getToken();
      if (token != null) await _sendTokenToBackend(token);
    } catch (_) {}
  }

  Future<void> _sendTokenToBackend(String token) async {
    try {
      final hasAuth = await ApiClient.instance.getToken();
      if (hasAuth == null) return;
      await ApiClient.instance.dio.post(
        '/device/token',
        data: {'token': token},
      );
    } catch (_) {}
  }

  Future<int> fetchUnreadCount() async {
    try {
      final res = await ApiClient.instance.dio.get('/notifications/unread-count');
      return (res.data['count'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<List<Map<String, dynamic>>> fetchNotifications() async {
    try {
      final res = await ApiClient.instance.dio.get('/notifications');
      final list = res.data as List<dynamic>;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> markAllRead() async {
    try {
      await ApiClient.instance.dio.patch('/notifications/all/read');
    } catch (_) {}
  }

  Future<void> markRead(String id) async {
    try {
      await ApiClient.instance.dio.patch('/notifications/$id/read');
    } catch (_) {}
  }
}

class UnreadCountNotifier extends ValueNotifier<int> {
  UnreadCountNotifier() : super(0);

  Future<void> refresh() async {
    value = await NotificationService.instance.fetchUnreadCount();
  }
}

final unreadCountNotifier = UnreadCountNotifier();
