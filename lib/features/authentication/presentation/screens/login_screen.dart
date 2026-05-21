import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../models/user_model.dart';
import '../../../../widgets/app_button.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String _role = 'student';
  bool _isLoggingIn = false;

  @override
  void initState() {
    super.initState();
    _email.text = 'student@college.edu';
    _password.text = 'password123';
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
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

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.startsWith('Exception: ')) {
      return text.substring('Exception: '.length);
    }
    return text;
  }

  void _navigateForUser(UserModel user) {
    if (user.isTeacher) {
      context.go('/teacher');
    } else if (user.isStudent) {
      context.go('/student');
    } else {
      _showError('Unsupported role: ${user.role}');
    }
  }

  Future<void> _login() async {
    if (_isLoggingIn) return;
    if (!_formKey.currentState!.validate()) return;

    ScaffoldMessenger.of(context).clearSnackBars();
    setState(() => _isLoggingIn = true);

    try {
      await ref
          .read(authStateProvider.notifier)
          .login(_email.text.trim(), _password.text);

      if (!mounted) return;

      final authState = ref.read(authStateProvider);
      if (authState.hasError) {
        _showError(_friendlyError(authState.error!));
        return;
      }

      final user = authState.valueOrNull;
      if (user == null) {
        _showError('Login failed. Please check your credentials.');
        return;
      }

      if (_role == 'teacher' && !user.isTeacher) {
        _showError('This account is not a teacher. Switch to Student.');
        await ref.read(authStateProvider.notifier).logout();
        return;
      }
      if (_role == 'student' && !user.isStudent) {
        _showError('This account is not a student. Switch to Teacher.');
        await ref.read(authStateProvider.notifier).logout();
        return;
      }

      _navigateForUser(user);
    } catch (e) {
      if (mounted) _showError(_friendlyError(e));
    } finally {
      if (mounted) setState(() => _isLoggingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final isLoading = authState.isLoading || _isLoggingIn;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                Icon(
                  Icons.verified_user,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Welcome Back',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign in to mark or manage attendance',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 32),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'student', label: Text('Student')),
                    ButtonSegment(value: 'teacher', label: Text('Teacher')),
                  ],
                  selected: {_role},
                  onSelectionChanged: (s) {
                    setState(() {
                      _role = s.first;
                      if (_role == 'teacher') {
                        _email.text = 'teacher@college.edu';
                        _password.text = 'password123';
                      } else {
                        _email.text = 'student@college.edu';
                        _password.text = 'password123';
                      }
                    });
                  },
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _email,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email),
                    hintText: 'Enter your email',
                  ),
                  keyboardType: TextInputType.emailAddress,
                  enabled: !isLoading,
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return 'Please enter your email';
                    }
                    if (!v.contains('@')) {
                      return 'Enter a valid email address';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _password,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock),
                    hintText: 'Enter your password',
                  ),
                  obscureText: true,
                  enabled: !isLoading,
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return 'Please enter your password';
                    }
                    if (v.length < 8) {
                      return 'Password must be at least 8 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                AppButton(
                  label: 'Sign In',
                  loading: isLoading,
                  onPressed: _login,
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: isLoading ? null : () => context.push('/register'),
                  child: const Text('Create new account'),
                ),
                const SizedBox(height: 24),
                Text(
                  'Server: ${ApiConfig.baseUrl}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
