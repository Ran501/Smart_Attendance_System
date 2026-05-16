import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/providers/auth_provider.dart';
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
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    // Prevent multiple login attempts
    if (_isLoggingIn) return;

    // Validate form
    if (!_formKey.currentState!.validate()) return;

    // Clear any previous errors
    ScaffoldMessenger.of(context).clearSnackBars();

    setState(() {
      _isLoggingIn = true;
    });

    try {
      // Attempt login
      await ref
          .read(authStateProvider.notifier)
          .login(_email.text.trim(), _password.text);

      if (!mounted) return;

      // Check authentication state after login
      final authState = ref.read(authStateProvider);

      await authState.when(
        data: (user) async {
          if (user != null) {
            // Successful login
            if (mounted) {
              // Navigate based on role
              if (user.isTeacher) {
                context.go('/teacher');
              } else {
                context.go('/student');
              }
            }
          } else {
            // User is null - login failed silently
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Login failed. Please check your credentials.'),
                  backgroundColor: Colors.red,
                  duration: Duration(seconds: 3),
                ),
              );
              setState(() {
                _isLoggingIn = false;
              });
            }
          }
        },
        loading: () {
          // Still loading, do nothing
        },
        error: (error, stackTrace) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Login failed: ${error.toString()}'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
              ),
            );
            setState(() {
              _isLoggingIn = false;
            });
          }
        },
      );
    } catch (e) {
      // Catch any unexpected errors
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('An error occurred: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
        setState(() {
          _isLoggingIn = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final isLoading = authState.isLoading || _isLoggingIn;

    // Listen for authentication success
    ref.listen(authStateProvider, (previous, next) {
      if (!mounted) return;

      next.whenOrNull(
        data: (user) {
          if (user != null && previous?.valueOrNull == null) {
            // Just logged in successfully
            if (user.isTeacher) {
              context.go('/teacher');
            } else {
              context.go('/student');
            }
          }
        },
        error: (error, stackTrace) {
          // Show error if not already showing
          if (previous?.isLoading == true) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Login failed: ${error.toString()}'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
              ),
            );
            // Reset logging in state
            if (_isLoggingIn) {
              setState(() {
                _isLoggingIn = false;
              });
            }
          }
        },
      );
    });

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
                    setState(() => _role = s.first);
                    // Optional: Auto-fill demo credentials based on role
                    if (_role == 'teacher') {
                      _email.text = 'teacher@college.edu';
                      _password.text = 'password123';
                    } else {
                      _email.text = 'student@college.edu';
                      _password.text = 'password123';
                    }
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
