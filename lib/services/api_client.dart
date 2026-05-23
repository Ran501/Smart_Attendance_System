import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/auth/session_auth_guard.dart';
import '../core/config/api_config.dart';

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  final _storage = const FlutterSecureStorage();
  late final Dio dio = _buildDio();

  Dio _buildDio() => Dio(
        BaseOptions(
          baseUrl: ApiConfig.baseUrl,
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
          headers: {'Content-Type': 'application/json'},
        ),
      )..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) async {
              final token = await _storage.read(key: 'auth_token');
              if (token != null) {
                options.headers['Authorization'] = 'Bearer $token';
              }
              handler.next(options);
            },
            onResponse: (response, handler) {
              SessionAuthGuard.reset();
              handler.next(response);
            },
            onError: (error, handler) {
              if (error is DioException) {
                SessionAuthGuard.recordFailure(error);
              }
              handler.next(error);
            },
          ),
        );

  Future<void> saveToken(String token) async {
    await _storage.write(key: 'auth_token', value: token);
    SessionAuthGuard.reset();
  }

  Future<void> clearToken() async {
    await _storage.delete(key: 'auth_token');
    SessionAuthGuard.reset();
  }

  Future<String?> getToken() => _storage.read(key: 'auth_token');

  static String messageFromDio(DioException error) {
    if (SessionAuthGuard.isBusinessUnauthorized(error)) {
      final data = error.response?.data;
      if (data is Map) {
        final msg = data['message'] ?? data['error'];
        if (msg != null) return msg.toString();
      }
    }

    if (SessionAuthGuard.isSessionAuthFailure(error)) {
      final hint = SessionAuthGuard.authRetryHint();
      final data = error.response?.data;
      final serverMsg = data is Map ? data['error']?.toString() : null;
      if (hint != null) {
        return '${serverMsg ?? 'Session problem'}. $hint.';
      }
      return serverMsg ?? 'Session expired. Please sign in again.';
    }

    final data = error.response?.data;
    if (data is Map) {
      if (data['error'] != null) {
        return data['error'].toString();
      }
      final errors = data['errors'];
      if (errors is List && errors.isNotEmpty) {
        return errors
            .map((e) {
              if (e is Map) {
                final field = e['path'] ?? e['param'];
                final msg = e['msg'] ?? e['message'];
                return field != null ? '$field: $msg' : '$msg';
              }
              return e.toString();
            })
            .join('\n');
      }
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Request timed out. Check your network connection.';
      case DioExceptionType.connectionError:
        return 'Cannot reach the cloud server. Check your internet connection and try again.';
      case DioExceptionType.badResponse:
        final code = error.response?.statusCode;
        if (code == 401) return 'Invalid email or password.';
        if (code == 409) return 'Email already registered.';
        return 'Server error (${code ?? 'unknown'}).';
      default:
        return error.message ?? 'Network request failed.';
    }
  }
}
