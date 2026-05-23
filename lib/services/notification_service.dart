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
    // Request permission (Android 13+, iOS)
    await _fcm.requestPermission(alert: true, badge: true, sound: true);

    // Create Android notification channel
    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Alerts when your attendance is at risk',
        importance: Importance.high,
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }

    // Init flutter_local_notifications
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _localNotifications.initialize(initSettings);

    // Handle notifications when app is in foreground
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // Register FCM token with backend
    await _registerToken();

    // Refresh token whenever it rotates
    _fcm.onTokenRefresh.listen(_sendTokenToBackend);
  }

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    await showLocalNotification(message);
  }

  Future<void> showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Alerts when your attendance is at risk',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(android: androidDetails),
    );
  }

  Future<void> _registerToken() async {
    try {
      final token = await _fcm.getToken();
      if (token != null) await _sendTokenToBackend(token);
    } catch (_) {}
  }

  Future<void> _sendTokenToBackend(String token) async {
    try {
      await ApiClient.instance.dio.post(
        '/device/token',
        data: {'token': token},
      );
    } catch (_) {}
  }

  // Fetch unread notification count from backend
  Future<int> fetchUnreadCount() async {
    try {
      final res = await ApiClient.instance.dio.get('/notifications/unread-count');
      return (res.data['count'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  // Fetch notification list from backend
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

// Provider-friendly notifier for unread count
class UnreadCountNotifier extends ValueNotifier<int> {
  UnreadCountNotifier() : super(0);

  Future<void> refresh() async {
    value = await NotificationService.instance.fetchUnreadCount();
  }
}

final unreadCountNotifier = UnreadCountNotifier();
