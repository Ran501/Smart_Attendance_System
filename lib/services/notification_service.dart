import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import 'api_client.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _fcm = FirebaseMessaging.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();

  static const _channelId = 'attendance_alerts';
  static const _channelName = 'Attendance Alerts';

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    await _requestPermissions();
    await _ensureNotificationChannels();
    await _initLocalPlugin();
    await _configureFcm();

    _initialized = true;
    await syncTokenWithBackend();
    _fcm.onTokenRefresh.listen(_sendTokenToBackend);
  }

  /// Background FCM isolate — channel + plugin must be set up here too.
  Future<void> ensureReadyForBackground() async {
    if (_initialized) return;
    await _ensureNotificationChannels();
    await _initLocalPlugin();
    _initialized = true;
  }

  Future<void> _requestPermissions() async {
    await _fcm.requestPermission(alert: true, badge: true, sound: true);

    if (Platform.isAndroid) {
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        await Permission.notification.request();
      }
    }

    if (Platform.isIOS) {
      await _fcm.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
  }

  Future<void> _ensureNotificationChannels() async {
    if (!Platform.isAndroid) return;

    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Live sessions and attendance alerts',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  Future<void> _initLocalPlugin() async {
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestSoundPermission: true,
        requestAlertPermission: true,
        requestBadgePermission: true,
      ),
    );
    await _localNotifications.initialize(initSettings);
  }

  Future<void> _configureFcm() async {
    FirebaseMessaging.onMessage.listen((message) async {
      await showLocalNotification(message);
      await unreadCountNotifier.refresh();
    });

    FirebaseMessaging.onMessageOpenedApp.listen((_) => unreadCountNotifier.refresh());
  }

  NotificationDetails _notificationDetails() {
    const android = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Live sessions and attendance alerts',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
      ticker: 'FacePass Bhutan',
    );

    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'default',
    );

    return const NotificationDetails(android: android, iOS: ios);
  }

  Future<void> showLocalNotification(RemoteMessage message) async {
    await ensureReadyForBackground();

    final notification = message.notification;
    final data = message.data;

    final title = notification?.title ?? data['title'] ?? _titleForType(data['type']);
    final body = notification?.body ?? data['body'];
    if (title == null || title.isEmpty || body == null || body.isEmpty) return;

    await _showTrayNotification(
      id: message.hashCode,
      title: title,
      body: body,
    );
  }

  /// Tray + sound when a live session starts (socket while app open, or manual).
  Future<void> showSessionStartedAlert({
    required String title,
    required String body,
    int? notificationId,
  }) async {
    await ensureReadyForBackground();
    await _showTrayNotification(
      id: notificationId ?? 'session_${DateTime.now().millisecondsSinceEpoch}'.hashCode,
      title: title,
      body: body,
    );
  }

  Future<void> showSessionStartedFromPayload(Map<String, dynamic> payload) async {
    final subject =
        payload['subjectName'] ?? payload['subject_name'] ?? payload['subject_code'] ?? 'Your module';
    final className = payload['className'] ?? payload['class_name'] ?? '';
    final range = payload['ble_max_distance_meters'] ?? payload['bleMaxDistanceMeters'] ?? 20;

    final title = 'Live attendance session';
    final body = className.toString().isNotEmpty
        ? '$subject ($className) is live. Mark attendance within $range m.'
        : '$subject is live. Mark attendance within $range m.';

    await showSessionStartedAlert(title: title, body: body);
  }

  Future<void> _showTrayNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    await _localNotifications.show(
      id,
      title,
      body,
      _notificationDetails(),
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

  Future<void> syncTokenWithBackend() async {
    try {
      final token = await _fcm.getToken();
      if (token != null) {
        await _sendTokenToBackend(token);
      } else if (kDebugMode) {
        debugPrint('[FCM] getToken() returned null — check google-services.json');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[FCM] syncTokenWithBackend: $e');
    }
  }

  Future<void> _sendTokenToBackend(String token) async {
    try {
      final hasAuth = await ApiClient.instance.getToken();
      if (hasAuth == null) {
        if (kDebugMode) debugPrint('[FCM] Skip token upload — not logged in');
        return;
      }
      await ApiClient.instance.dio.post('/device/token', data: {'token': token});
      if (kDebugMode) debugPrint('[FCM] Device token registered with backend');
    } catch (e) {
      if (kDebugMode) debugPrint('[FCM] Token upload failed: $e');
    }
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
