import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../widgets/app_button.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _studentId = TextEditingController();
  String _role = 'student';
  bool _isRegistering = false;

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.startsWith('Exception: ')) {
      return text.substring('Exception: '.length);
    }
    return text;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _register() async {
    if (_isRegistering) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isRegistering = true);
    ScaffoldMessenger.of(context).clearSnackBars();

    try {
      final studentIdRaw = _studentId.text.trim();
      await ref.read(authStateProvider.notifier).register(
            email: _email.text.trim(),
            password: _password.text,
            fullName: _name.text.trim(),
            role: _role,
            studentId: _role == 'student' && studentIdRaw.isNotEmpty
                ? studentIdRaw
                : null,
          );

      if (!mounted) return;

      final authState = ref.read(authStateProvider);
      if (authState.hasError) {
        _showError(_friendlyError(authState.error!));
        return;
      }

      final user = authState.valueOrNull;
      if (user == null) {
        _showError('Registration failed. Please try again.');
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account created successfully'),
            backgroundColor: Colors.green,
          ),
        );
        if (user.isStudent) {
          context.go('/face-register');
        } else if (user.isTeacher) {
          context.go('/teacher');
        } else {
          context.go('/login');
        }
      }
    } catch (e) {
      if (mounted) _showError(_friendlyError(e));
    } finally {
      if (mounted) setState(() => _isRegistering = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _studentId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(authStateProvider).isLoading || _isRegistering;

    return Scaffold(
      appBar: AppBar(title: const Text('Register')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: const [
                  DropdownMenuItem(value: 'student', child: Text('Student')),
                  DropdownMenuItem(value: 'teacher', child: Text('Teacher')),
                ],
                onChanged: loading ? null : (v) => setState(() => _role = v ?? 'student'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                enabled: !loading,
                decoration: const InputDecoration(labelText: 'Full Name'),
                validator: (v) =>
                    v != null && v.trim().isNotEmpty ? null : 'Full name is required',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _email,
                enabled: !loading,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  hintText: 'you@college.edu',
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Email is required';
                  }
                  if (!v.contains('@') || !v.contains('.')) {
                    return 'Enter a valid email address';
                  }
                  return null;
                },
              ),
              if (_role == 'student') ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _studentId,
                  enabled: !loading,
                  decoration: const InputDecoration(
                    labelText: 'Student ID',
                    hintText: 'e.g. STU-2024-042',
                  ),
                  validator: (v) {
                    if (_role != 'student') return null;
                    if (v == null || v.trim().isEmpty) {
                      return 'Student ID is required';
                    }
                    if (v.trim().length < 3) {
                      return 'Student ID is too short';
                    }
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _password,
                enabled: !loading,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  hintText: 'At least 8 characters',
                ),
                obscureText: true,
                validator: (v) =>
                    v != null && v.length >= 8 ? null : 'Password must be at least 8 characters',
              ),
              const SizedBox(height: 24),
              AppButton(
                label: 'Create Account',
                loading: loading,
                onPressed: _register,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: loading ? null : () => context.go('/login'),
                child: const Text('Already have an account? Sign in'),
              ),
              const SizedBox(height: 16),
              Text(
                'Server: ${AppConstants.apiBaseUrl}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
