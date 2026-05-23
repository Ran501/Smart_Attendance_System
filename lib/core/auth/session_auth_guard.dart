import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Distinguishes "face not recognized" 401/403 from real session expiry.
class SessionAuthGuard {
  SessionAuthGuard._();

  static const int maxFailuresBeforeRelogin = 3;

  static final ValueNotifier<int> failureCount = ValueNotifier(0);
  static VoidCallback? onReloginRequired;

  static void reset() => failureCount.value = 0;

  static bool isBusinessUnauthorized(DioException error) {
    final status = error.response?.statusCode;
    if (status != 401 && status != 403) return false;

    final path = error.requestOptions.path.toLowerCase();
    if (path.contains('/face/verify')) return true;

    final data = error.response?.data;
    if (data is! Map) return false;

    if (data['verified'] == false) return true;
    if (data['accepted'] == false) return true;

    final msg = (data['message'] ?? data['error'] ?? '').toString().toLowerCase();
    return msg.contains('face not recognized') ||
        msg.contains('face mismatch') ||
        msg.contains('face match');
  }

  static bool isSessionAuthFailure(DioException error) {
    final status = error.response?.statusCode;
    if (status != 401 && status != 403) return false;

    final path = error.requestOptions.path.toLowerCase();
    if (path.contains('/auth/login') || path.contains('/auth/register')) {
      return false;
    }

    return !isBusinessUnauthorized(error);
  }

  static void recordFailure(DioException error) {
    if (!isSessionAuthFailure(error)) return;

    failureCount.value++;
    if (failureCount.value >= maxFailuresBeforeRelogin) {
      failureCount.value = 0;
      onReloginRequired?.call();
    }
  }

  static String? authRetryHint() {
    final left = maxFailuresBeforeRelogin - failureCount.value;
    if (left <= 0 || left >= maxFailuresBeforeRelogin) return null;
    return '$left retry${left == 1 ? '' : 'ies'} left before sign-in required';
  }
}
