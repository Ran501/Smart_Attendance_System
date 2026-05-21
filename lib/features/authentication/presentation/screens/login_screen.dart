import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../models/user_model.dart';
import '../../../../widgets/app_button.dart';
import '../../../../widgets/enterprise_shell.dart';

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
  bool _rememberMe = true;
  bool _hidePassword = true;

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
      SnackBar(content: Text(message), backgroundColor: Colors.red, duration: const Duration(seconds: 4)),
    );
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.startsWith('Exception: ')) return text.substring('Exception: '.length);
    return text;
  }

  void _navigateForUser(UserModel user) {
    if (user.isTeacher || user.isAdmin) {
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
      await ref.read(authStateProvider.notifier).login(_email.text.trim(), _password.text);
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

      if (_role == 'teacher' && !user.isTeacher && !user.isAdmin) {
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

  void _googleNotReady() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Google Sign-In UI is ready, but your current backend/database auth is still email-password. Add a backend OAuth endpoint before enabling it.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final isLoading = authState.isLoading || _isLoggingIn;
    final scheme = Theme.of(context).colorScheme;

    return EnterpriseScaffold(
      safeArea: false,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth > 820;
                final brand = _BrandPanel(wide: wide).animate().fadeIn(duration: 500.ms).slideX(begin: -0.05);
                final form = _LoginPanel(
                  formKey: _formKey,
                  email: _email,
                  password: _password,
                  role: _role,
                  rememberMe: _rememberMe,
                  hidePassword: _hidePassword,
                  isLoading: isLoading,
                  onRoleChanged: (role) {
                    setState(() {
                      _role = role;
                      if (_role == 'teacher') {
                        _email.text = 'teacher@college.edu';
                      } else {
                        _email.text = 'student@college.edu';
                      }
                      _password.text = 'password123';
                    });
                  },
                  onRememberChanged: (value) => setState(() => _rememberMe = value),
                  onTogglePassword: () => setState(() => _hidePassword = !_hidePassword),
                  onLogin: _login,
                  onGoogle: _googleNotReady,
                ).animate().fadeIn(duration: 650.ms).slideY(begin: 0.04);

                if (wide) {
                  return Row(
                    children: [
                      Expanded(child: brand),
                      const SizedBox(width: 24),
                      SizedBox(width: 470, child: form),
                    ],
                  );
                }
                return Column(children: [brand, const SizedBox(height: 20), form]);
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  final bool wide;
  const _BrandPanel({required this.wide});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassCard(
      padding: EdgeInsets.all(wide ? 34 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [scheme.primary, scheme.secondary]),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(Icons.face_retouching_natural, color: Colors.white, size: 30),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppConstants.appName, style: Theme.of(context).textTheme.titleLarge),
                  Text('Bhutan Smart Campus', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ],
          ),
          SizedBox(height: wide ? 58 : 28),
          Text(
            'Secure attendance for modern Bhutanese institutions.',
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          Text(
            'Face recognition, BLE proximity, campus WiFi, geo-fencing, QR backup, and real-time dashboards in one enterprise-ready system.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 28),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: const [
              StatusPill(label: 'AI FaceNet', icon: Icons.auto_awesome, color: Color(0xFF1E4ED8)),
              StatusPill(label: 'BLE Ready', icon: Icons.bluetooth, color: Color(0xFF10B981)),
              StatusPill(label: 'Geo + WiFi', icon: Icons.location_on_outlined, color: Color(0xFFF59E0B)),
            ],
          ),
          const SizedBox(height: 28),
          GlassCard(
            padding: const EdgeInsets.all(16),
            color: scheme.primary.withValues(alpha: 0.10),
            child: Row(
              children: [
                Icon(Icons.verified_user_outlined, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Role-aware login sends teachers to analytics and students to live attendance.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginPanel extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController email;
  final TextEditingController password;
  final String role;
  final bool rememberMe;
  final bool hidePassword;
  final bool isLoading;
  final ValueChanged<String> onRoleChanged;
  final ValueChanged<bool> onRememberChanged;
  final VoidCallback onTogglePassword;
  final VoidCallback onLogin;
  final VoidCallback onGoogle;

  const _LoginPanel({
    required this.formKey,
    required this.email,
    required this.password,
    required this.role,
    required this.rememberMe,
    required this.hidePassword,
    required this.isLoading,
    required this.onRoleChanged,
    required this.onRememberChanged,
    required this.onTogglePassword,
    required this.onLogin,
    required this.onGoogle,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(26),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Welcome back', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text('Sign in to FacePass Bhutan', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 24),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'student', label: Text('Student'), icon: Icon(Icons.school_outlined)),
                ButtonSegment(value: 'teacher', label: Text('Teacher'), icon: Icon(Icons.co_present_outlined)),
              ],
              selected: {role},
              onSelectionChanged: isLoading ? null : (s) => onRoleChanged(s.first),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: email,
              decoration: const InputDecoration(labelText: 'Institution email', prefixIcon: Icon(Icons.mail_outline)),
              keyboardType: TextInputType.emailAddress,
              enabled: !isLoading,
              validator: (v) {
                if (v == null || v.isEmpty) return 'Please enter your email';
                if (!v.contains('@')) return 'Enter a valid email address';
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: password,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: onTogglePassword,
                ),
              ),
              obscureText: hidePassword,
              enabled: !isLoading,
              validator: (v) {
                if (v == null || v.isEmpty) return 'Please enter your password';
                if (v.length < 8) return 'Password must be at least 8 characters';
                return null;
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Checkbox(value: rememberMe, onChanged: isLoading ? null : (v) => onRememberChanged(v ?? true)),
                const Text('Remember me'),
                const Spacer(),
                TextButton(onPressed: isLoading ? null : () {}, child: const Text('Forgot?')),
              ],
            ),
            const SizedBox(height: 14),
            AppButton(label: 'Sign In', icon: Icons.arrow_forward_rounded, loading: isLoading, onPressed: onLogin),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: isLoading ? null : onGoogle,
              icon: const Icon(Icons.g_mobiledata, size: 28),
              label: const Text('Continue with Google'),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: isLoading ? null : () => context.push('/register'),
              child: const Text('Create a new account'),
            ),
            const SizedBox(height: 12),
            Text(
              'Server: ${ApiConfig.baseUrl}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
