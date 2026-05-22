import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-device saved logins when "Remember me" is enabled.
class LoginPreferencesService {
  static const _rememberKey = 'login_remember_me';
  static const _emailsKey = 'login_saved_emails';
  static const _lastEmailKey = 'login_last_email';
  static const _lastRoleKey = 'login_last_role';

  Future<bool> getRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_rememberKey) ?? true;
  }

  Future<void> setRememberMe(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberKey, value);
    if (!value) {
      await prefs.remove(_lastEmailKey);
    }
  }

  Future<List<String>> getSavedEmails() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_emailsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => e.toString().trim().toLowerCase()).where((e) => e.contains('@')).toSet().toList();
    } catch (_) {
      return [];
    }
  }

  Future<String?> getLastEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastEmailKey);
  }

  Future<String> getLastRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastRoleKey) ?? 'student';
  }

  Future<void> saveSuccessfulLogin({
    required String email,
    required String role,
    required bool rememberMe,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberKey, rememberMe);
    if (!rememberMe) return;

    final normalized = email.trim().toLowerCase();
    await prefs.setString(_lastEmailKey, normalized);
    await prefs.setString(_lastRoleKey, role);

    final existing = await getSavedEmails();
    final updated = [normalized, ...existing.where((e) => e != normalized)];
    await prefs.setString(_emailsKey, jsonEncode(updated.take(8).toList()));
  }

  Future<({String? email, String role, List<String> suggestions})> loadForLoginForm() async {
    final remember = await getRememberMe();
    final suggestions = await getSavedEmails();
    if (!remember) {
      return (email: null, role: await getLastRole(), suggestions: suggestions);
    }
    return (
      email: await getLastEmail(),
      role: await getLastRole(),
      suggestions: suggestions,
    );
  }
}
