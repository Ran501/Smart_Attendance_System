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

  /// v2 channel — Android channels cannot change sound after creation; use a new id.
  static const _channelId = 'attendance_alerts_v2';
  static const _channelName = 'Attendance Alerts';
  static const _legacyChannelId = 'attendance_alerts';

  bool _initialized = false;

  /// Live-session tray alerts already shown this app run (by session id).
  final Set<String> _announcedLiveSessionIds = {};

  /// In-app tray already shown for these notification row ids.
  final Set<String> _trayShownNotificationIds = {};

  Future<void> initialize() async {
    if (_initialized) return;
    await _requestPermissions();
    await _ensureNotificationChannels();
    await _initLocalPlugin();
    await _configureFcm();

    _initialized = true;
    _fcm.onTokenRefresh.listen(_sendTokenToBackend);
  }

  Future<void> ensureReadyForBackground() async {
    if (_initialized) return;
    await _ensureNotificationChannels();
    await _initLocalPlugin();
    _initialized = true;
  }

  /// After login / restore session: register FCM token and alert unread with sound.
  Future<void> afterAuthReady({bool soundForUnread = true}) async {
    await syncTokenWithBackend();
    await unreadCountNotifier.refresh();
    if (soundForUnread && unreadCountNotifier.value > 0) {
      await alertLatestUnreadWithSound();
    }
  }

  /// Shows the newest unread notification in the phone tray with sound (e.g. on login).
  Future<void> alertLatestUnreadWithSound() async {
    try {
      final items = await fetchNotifications();
      final unread = items.where((n) => n['is_read'] != true).toList();
      if (unread.isEmpty) return;

      final latest = unread.first;
      final title = (latest['title'] as String?)?.trim();
      final body = (latest['body'] as String?)?.trim();
      if (title == null || title.isEmpty || body == null || body.isEmpty) return;

      await _showTrayNotification(
        id: 'unread_${latest['id'] ?? DateTime.now().millisecondsSinceEpoch}'.hashCode,
        title: title,
        body: body,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Notify] alertLatestUnread: $e');
    }
  }

  Future<void> _requestPermissions() async {
    await _fcm.requestPermission(alert: true, badge: true, sound: true);

    if (Platform.isAndroid) {
      var status = await Permission.notification.status;
      if (!status.isGranted) {
        status = await Permission.notification.request();
      }
      if (kDebugMode && !status.isGranted) {
        debugPrint('[Notify] Android notification permission denied');
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

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.deleteNotificationChannel(_legacyChannelId);

    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Live sessions and attendance alerts with sound',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      showBadge: true,
      audioAttributesUsage: AudioAttributesUsage.notification,
    );

    await androidPlugin?.createNotificationChannel(channel);
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

    FirebaseMessaging.onMessageOpenedApp.listen((_) {
      unreadCountNotifier.refresh();
      alertLatestUnreadWithSound();
    });

    final initial = await _fcm.getInitialMessage();
    if (initial != null) {
      await unreadCountNotifier.refresh();
    }
  }

  NotificationDetails _notificationDetails() {
    const android = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Live sessions and attendance alerts with sound',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
      ticker: 'FacePass Bhutan',
      category: AndroidNotificationCategory.message,
      audioAttributesUsage: AudioAttributesUsage.notification,
      visibility: NotificationVisibility.public,
    );

    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'default',
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    return const NotificationDetails(android: android, iOS: ios);
  }

  Future<void> showLocalNotification(RemoteMessage message) async {
    await ensureReadyForBackground();

    final notification = message.notification;
    final data = message.data;
    final type = data['type']?.toString() ?? '';

    if (type == 'SESSION_STARTED') {
      await showLiveSessionFromPayloadOnce(Map<String, dynamic>.from(data));
      await unreadCountNotifier.refresh();
      return;
    }

    final title = notification?.title ?? data['title'] ?? _titleForType(type);
    final body = notification?.body ?? data['body'];
    if (title == null || title.isEmpty || body == null || body.isEmpty) return;

    await _showTrayNotification(
      id: message.hashCode,
      title: title,
      body: body,
    );
  }

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

  String? _sessionIdFromPayload(Map<String, dynamic> payload) {
    final raw = payload['sessionId'] ??
        payload['session_id'] ??
        payload['id'];
    final id = raw?.toString().trim();
    return (id == null || id.isEmpty) ? null : id;
  }

  /// Show live-session tray once per session id (socket + FCM safe).
  Future<void> showLiveSessionFromPayloadOnce(Map<String, dynamic> payload) async {
    final sessionId = _sessionIdFromPayload(payload);
    if (sessionId != null) {
      if (_announcedLiveSessionIds.contains(sessionId)) return;
      _announcedLiveSessionIds.add(sessionId);
    }

    final subject =
        payload['subjectName'] ?? payload['subject_name'] ?? payload['subject_code'] ?? 'Your module';
    final className = payload['className'] ?? payload['class_name'] ?? '';
    final range = payload['ble_max_distance_meters'] ?? payload['bleMaxDistanceMeters'] ?? 20;

    const title = 'Live attendance session';
    final body = className.toString().isNotEmpty
        ? '$subject ($className) is live. Mark attendance within $range m.'
        : '$subject is live. Mark attendance within $range m.';

    await showSessionStartedAlert(
      title: title,
      body: body,
      notificationId: sessionId?.hashCode,
    );
  }

  @Deprecated('Use showLiveSessionFromPayloadOnce')
  Future<void> showSessionStartedFromPayload(Map<String, dynamic> payload) =>
      showLiveSessionFromPayloadOnce(payload);

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
      case 'ATTENDANCE_WARNING':
      case 'ATTENDANCE_DANGER':
        return 'Attendance warning';
      case 'TEACHER_ATTENDANCE_ALERT':
        return 'Attendance alert';
      default:
        return null;
    }
  }

  static const _attendanceAlertTypes = {
    'ATTENDANCE_WARNING',
    'ATTENDANCE_DANGER',
    'TEACHER_ATTENDANCE_ALERT',
  };

  DateTime? _parseCreatedAt(Map<String, dynamic> item) {
    final raw = item['created_at'] ?? item['createdAt'];
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString())?.toLocal();
  }

  /// Refresh bell only — no tray popup (use after background data sync).
  Future<void> refreshUnreadBell() async {
    await unreadCountNotifier.refresh();
  }

  /// Show tray for new attendance-warning rows only (not live session).
  Future<void> pulseAttendanceAlertsTray({Duration maxAge = const Duration(minutes: 2)}) async {
    try {
      await unreadCountNotifier.refresh();
      final items = await fetchNotifications();
      final cutoff = DateTime.now().subtract(maxAge);

      for (final item in items) {
        if (item['is_read'] == true) continue;
        final type = item['type']?.toString() ?? '';
        if (!_attendanceAlertTypes.contains(type)) continue;

        final id = item['id']?.toString();
        if (id != null && _trayShownNotificationIds.contains(id)) continue;

        final created = _parseCreatedAt(item);
        if (created != null && created.isBefore(cutoff)) continue;

        final title = (item['title'] as String?)?.trim();
        final body = (item['body'] as String?)?.trim();
        if (title == null || title.isEmpty || body == null || body.isEmpty) continue;

        if (id != null) _trayShownNotificationIds.add(id);
        await _showTrayNotification(
          id: id?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
          title: title,
          body: body,
        );
        break;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Notify] pulseAttendanceAlertsTray: $e');
    }
  }

  /// Prefer attendance-only tray; never re-shows old live-session unread rows.
  Future<void> pulseUnreadTray() async {
    await pulseAttendanceAlertsTray();
  }

  Future<void> syncTokenWithBackend() async {
    try {
      final token = await _fcm.getToken();
      if (token != null) {
        await _sendTokenToBackend(token);
      } else if (kDebugMode) {
        debugPrint('[FCM] getToken() null — add google-services.json and rebuild');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[FCM] syncToken: $e');
    }
  }

  Future<void> _sendTokenToBackend(String token) async {
    try {
      final hasAuth = await ApiClient.instance.getToken();
      if (hasAuth == null) return;
      await ApiClient.instance.dio.post('/device/token', data: {'token': token});
      if (kDebugMode) debugPrint('[FCM] Device token saved on server');
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
