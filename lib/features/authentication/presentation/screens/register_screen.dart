import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../widgets/app_brand_logo.dart';
import '../../../../widgets/app_button.dart';
import '../../../../widgets/enterprise_shell.dart';

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
  bool _hidePassword = true;

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.startsWith('Exception: ')) return text.substring('Exception: '.length);
    return text;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red, duration: const Duration(seconds: 4)),
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
            studentId: studentIdRaw.isNotEmpty ? studentIdRaw : null,
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

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account created successfully'), backgroundColor: Colors.green),
      );
      if (user.isStudent) {
        context.go('/face-register');
      } else if (user.isTeacher || user.isAdmin) {
        context.go('/teacher');
      } else {
        context.go('/login');
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
    final scheme = Theme.of(context).colorScheme;

    return EnterpriseScaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/login')),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 86, 20, 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: GlassCard(
              padding: const EdgeInsets.all(26),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        AppBrandLogo.compact(),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Create institution account', style: Theme.of(context).textTheme.headlineSmall),
                              Text(
                                'Students complete AI face enrolment after sign-up.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'student', label: Text('Student'), icon: Icon(Icons.school_outlined)),
                        ButtonSegment(value: 'teacher', label: Text('Teacher'), icon: Icon(Icons.co_present_outlined)),
                      ],
                      selected: {_role},
                      onSelectionChanged: loading ? null : (s) => setState(() => _role = s.first),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _name,
                      enabled: !loading,
                      decoration: const InputDecoration(labelText: 'Full Name', prefixIcon: Icon(Icons.badge_outlined)),
                      validator: (v) => v != null && v.trim().isNotEmpty ? null : 'Full name is required',
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _studentId,
                      enabled: !loading,
                      decoration: InputDecoration(
                        labelText: _role == 'student' ? 'Student ID / CID' : 'Staff ID / CID',
                        prefixIcon: const Icon(Icons.credit_card_outlined),
                      ),
                      validator: (v) {
                        if (_role != 'student') return null;
                        if (v == null || v.trim().isEmpty) return 'Student ID / CID is required';
                        if (v.trim().length < 3) return 'ID is too short';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _email,
                      enabled: !loading,
                      decoration: const InputDecoration(labelText: 'Email', hintText: 'you@college.edu', prefixIcon: Icon(Icons.mail_outline)),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Email is required';
                        if (!v.contains('@') || !v.contains('.')) return 'Enter a valid email address';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      enabled: !loading,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _hidePassword = !_hidePassword),
                        ),
                      ),
                      obscureText: _hidePassword,
                      validator: (v) => v != null && v.length >= 8 ? null : 'Password must be at least 8 characters',
                    ),
                    const SizedBox(height: 22),
                    AppButton(label: 'Create Account', icon: Icons.verified_user_outlined, loading: loading, onPressed: _register),
                    const SizedBox(height: 12),
                    TextButton(onPressed: loading ? null : () => context.go('/login'), child: const Text('Already have an account? Sign in')),
                  ],
                ),
              ),
            ).animate().fadeIn(duration: 600.ms).slideY(begin: 0.04),
          ),
        ),
      ),
    );
  }
}
