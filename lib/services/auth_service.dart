import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import 'api_client.dart';

class AuthService {
  final _api = ApiClient.instance;

  Future<({String token, UserModel user})> login(String email, String password) async {
    try {
      final res = await _api.dio.post('/auth/login', data: {
        'email': email,
        'password': password,
      });
      final token = res.data['token'] as String;
      final user = UserModel.fromJson(res.data['user'] as Map<String, dynamic>);
      await _api.saveToken(token);
      await _persistUser(user);
      return (token: token, user: user);
    } on DioException catch (e) {
      throw Exception(ApiClient.messageFromDio(e));
    }
  }

  Future<({String token, UserModel user})> register({
    required String email,
    required String password,
    required String fullName,
    required String role,
    String? studentId,
  }) async {
    try {
      final res = await _api.dio.post('/auth/register', data: {
        'email': email,
        'password': password,
        'fullName': fullName,
        'role': role,
        if (studentId != null) 'studentId': studentId,
      });
      final token = res.data['token'] as String;
      final user = UserModel.fromJson(res.data['user'] as Map<String, dynamic>);
      await _api.saveToken(token);
      await _persistUser(user);
      return (token: token, user: user);
    } on DioException catch (e) {
      throw Exception(ApiClient.messageFromDio(e));
    }
  }

  Future<UserModel?> restoreSession() async {
    final token = await _api.getToken();
    if (token == null) return null;
    try {
      final res = await _api.dio.get('/auth/me');
      final user = UserModel.fromJson(res.data as Map<String, dynamic>);
      await _persistUser(user);
      return user;
    } catch (_) {
      await logout();
      return null;
    }
  }

  Future<void> logout() async {
    await _api.clearToken();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cached_user');
  }

  Future<void> _persistUser(UserModel user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cached_user', jsonEncode(user.toJson()));
  }

  Future<UserModel?> getCachedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('cached_user');
    if (raw == null) return null;
    return UserModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}
