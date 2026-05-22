import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../models/user_model.dart';
import '../../../../services/login_preferences_service.dart';
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
  final _loginPrefs = LoginPreferencesService();
  String _role = 'student';
  bool _isLoggingIn = false;
  bool _rememberMe = true;
  bool _hidePassword = true;
  List<String> _emailSuggestions = [];
  bool _prefsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadSavedLogin();
  }

  Future<void> _loadSavedLogin() async {
    final saved = await _loginPrefs.loadForLoginForm();
    final remember = await _loginPrefs.getRememberMe();
    if (!mounted) return;
    setState(() {
      _rememberMe = remember;
      _emailSuggestions = saved.suggestions;
      if (saved.email != null && saved.email!.isNotEmpty) {
        _email.text = saved.email!;
      }
      _role = saved.role;
      _prefsLoaded = true;
    });
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

      await _loginPrefs.saveSuccessfulLogin(
        email: _email.text.trim(),
        role: _role,
        rememberMe: _rememberMe,
      );

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
    final isLoading = authState.isLoading || _isLoggingIn || !_prefsLoaded;

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
                  emailSuggestions: _emailSuggestions,
                  onRoleChanged: (role) {
                    setState(() => _role = role);
                  },
                  onRememberChanged: (value) async {
                    setState(() => _rememberMe = value);
                    await _loginPrefs.setRememberMe(value);
                  },
                  onTogglePassword: () => setState(() => _hidePassword = !_hidePassword),
                  onLogin: _login,
                ).animate().fadeIn(duration: 650.ms).slideY(begin: 0.04);

                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: brand),
                      const SizedBox(width: 24),
                      Flexible(child: form),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppConstants.appName, style: Theme.of(context).textTheme.titleLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
                    Text('Bhutan Smart Campus', style: Theme.of(context).textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
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
  final List<String> emailSuggestions;
  final ValueChanged<String> onRoleChanged;
  final ValueChanged<bool> onRememberChanged;
  final VoidCallback onTogglePassword;
  final VoidCallback onLogin;

  const _LoginPanel({
    required this.formKey,
    required this.email,
    required this.password,
    required this.role,
    required this.rememberMe,
    required this.hidePassword,
    required this.isLoading,
    required this.emailSuggestions,
    required this.onRoleChanged,
    required this.onRememberChanged,
    required this.onTogglePassword,
    required this.onLogin,
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
              decoration: const InputDecoration(
                labelText: 'Institution email',
                prefixIcon: Icon(Icons.mail_outline),
              ),
              keyboardType: TextInputType.emailAddress,
              enabled: !isLoading,
              validator: (v) {
                if (v == null || v.isEmpty) return 'Please enter your email';
                if (!v.contains('@')) return 'Enter a valid email address';
                return null;
              },
            ),
            if (rememberMe && emailSuggestions.isNotEmpty) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Saved on this device',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: emailSuggestions.map((savedEmail) {
                  return ActionChip(
                    avatar: const Icon(Icons.person_outline, size: 18),
                    label: Text(savedEmail),
                    onPressed: isLoading ? null : () => email.text = savedEmail,
                  );
                }).toList(),
              ),
            ],
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
                Checkbox(
                  value: rememberMe,
                  onChanged: isLoading ? null : (v) => onRememberChanged(v ?? true),
                ),
                const Flexible(
                  child: Text('Remember me on this device'),
                ),
                TextButton(onPressed: isLoading ? null : () {}, child: const Text('Forgot?')),
              ],
            ),
            const SizedBox(height: 14),
            AppButton(label: 'Sign In', icon: Icons.arrow_forward_rounded, loading: isLoading, onPressed: onLogin),
            const SizedBox(height: 14),
            TextButton(
              onPressed: isLoading ? null : () => context.push('/register'),
              child: const Text('Create a new account'),
            ),
          ],
        ),
      ),
    );
  }
}
