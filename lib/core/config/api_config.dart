import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// API base URL for the Smart Attendance backend.
///
/// Physical Android device: set [devLanHost] to your PC's Wi‑Fi IPv4 address
/// (run `ipconfig` on Windows) and ensure the phone is on the same network.
///
/// Android emulator: use `--dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1`
///
/// USB debugging: run `adb reverse tcp:3000 tcp:3000` then use
/// `--dart-define=API_BASE_URL=http://127.0.0.1:3000/api/v1`
class ApiConfig {
  static const String _envUrl = String.fromEnvironment('API_BASE_URL');

  /// Your development machine's LAN IP (same Wi‑Fi as the phone).
  static const String devLanHost = '10.236.218.179';

  static const int devPort = 3000;
  static const String apiPath = '/api/v1';

  static String get baseUrl {
    if (_envUrl.isNotEmpty) return _envUrl;

    if (kIsWeb) {
      return 'http://localhost:$devPort$apiPath';
    }

    if (!kIsWeb && Platform.isAndroid) {
      return 'http://$devLanHost:$devPort$apiPath';
    }

    if (!kIsWeb && Platform.isIOS) {
      return 'http://localhost:$devPort$apiPath';
    }

    return 'http://localhost:$devPort$apiPath';
  }
}
