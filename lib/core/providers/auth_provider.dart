import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authStateProvider =
    AsyncNotifierProvider<AuthNotifier, UserModel?>(AuthNotifier.new);

class AuthNotifier extends AsyncNotifier<UserModel?> {
  @override
  Future<UserModel?> build() async {
    final service = ref.read(authServiceProvider);
    return service.restoreSession();
  }

  Future<void> login(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final result = await ref.read(authServiceProvider).login(email, password);
      return result.user;
    });
  }

  Future<void> register({
    required String email,
    required String password,
    required String fullName,
    required String role,
    String? studentId,
    String? department,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final result = await ref.read(authServiceProvider).register(
            email: email,
            password: password,
            fullName: fullName,
            role: role,
            studentId: studentId,
            department: department,
          );
      return result.user;
    });
  }

  Future<void> logout() async {
    await ref.read(authServiceProvider).logout();
    state = const AsyncData(null);
  }
}
