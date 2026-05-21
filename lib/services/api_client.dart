import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/constants/app_constants.dart';
import '../core/config/api_config.dart';

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  final _storage = const FlutterSecureStorage();
  late final Dio dio = Dio(
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
        onError: (error, handler) {
          if (error.response?.statusCode == 401) {
            _storage.delete(key: 'auth_token');
          }
          handler.next(error);
        },
      ),
    );

  Future<void> saveToken(String token) =>
      _storage.write(key: 'auth_token', value: token);

  Future<void> clearToken() => _storage.delete(key: 'auth_token');

  Future<String?> getToken() => _storage.read(key: 'auth_token');

  static String messageFromDio(DioException error) {
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
        return 'Cannot reach the server at ${ApiConfig.baseUrl}. '
            'Start the backend (npm start in backend/) and verify devLanHost in '
            'lib/core/config/api_config.dart matches your PC IP.';
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
