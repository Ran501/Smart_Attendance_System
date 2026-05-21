import 'package:flutter/foundation.dart';

/// API base URL for the Smart Attendance backend.
class ApiConfig {
  static const String _envUrl = String.fromEnvironment('API_BASE_URL');

  static const String productionUrl =
      'https://smartattendancesystem-production-5b56.up.railway.app/api/v1';

  static String get baseUrl {
    if (_envUrl.isNotEmpty) return _envUrl;
    return productionUrl;
  }
}