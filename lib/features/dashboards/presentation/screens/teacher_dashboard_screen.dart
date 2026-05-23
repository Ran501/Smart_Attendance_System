import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../models/attendance_session_model.dart';
import '../../../../services/attendance_service.dart';
import '../../../../services/catalog_service.dart';
import '../../../../services/realtime_socket.dart';
import '../../../../widgets/app_button.dart';
import '../../../../widgets/enterprise_shell.dart';

class TeacherDashboardScreen extends ConsumerStatefulWidget {
  const TeacherDashboardScreen({super.key});

  @override
  ConsumerState<TeacherDashboardScreen> createState() => _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState extends ConsumerState<TeacherDashboardScreen> {
  List<Map<String, dynamic>> _modules = [];
  List<AttendanceSessionModel> _activeSessions = [];
  bool _loading = false;
  String? _modulesError;
  String? _sessionsError;
  final _realtime = RealtimeAttendanceSocket();
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && !_loading) _loadQuiet();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _realtime.disconnect();
    super.dispose();
  }

  String _classIdFromModule(Map<String, dynamic> module) {
    return (module['class_id'] ??
            module['classId'] ??
            module['class'] ??
            '')
        .toString();
  }

  void _connectRealtime() {
    final classIds = _modules.map(_classIdFromModule).where((id) => id.isNotEmpty).toSet();
    _realtime.connect(
      classIds: classIds,
      onDataChanged: () {
        if (mounted) _loadQuiet();
      },
    );
  }

  /// Refresh without full-screen loading spinner (socket / poll).
  Future<void> _loadQuiet() async {
    try {
      final modules = await CatalogService().getTeacherModules();
      final sessions = await AttendanceService().getActiveSessions();
      if (!mounted) return;
      setState(() {
        _modules = modules;
        _activeSessions = sessions;
        _modulesError = null;
        _sessionsError = null;
      });
      _connectRealtime();
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _modulesError = null;
      _sessionsError = null;
    });

    List<Map<String, dynamic>> modules = [];
    List<AttendanceSessionModel> sessions = [];
    String? modulesError;
    String? sessionsError;

    try {
      modules = await CatalogService().getTeacherModules();
    } catch (e) {
      modulesError = e.toString().replaceFirst('Exception: ', '');
    }

    try {
      sessions = await AttendanceService().getActiveSessions();
    } catch (e) {
      sessionsError = e.toString().replaceFirst('Exception: ', '');
    }

    if (mounted) {
      setState(() {
        _modules = modules;
        _activeSessions = sessions;
        _modulesError = modulesError;
        _sessionsError = sessionsError;
        _loading = false;
      });

      if (modulesError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load modules: $modulesError'), backgroundColor: Colors.red),
        );
      } else if (sessionsError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Modules loaded, but active sessions failed: $sessionsError'), backgroundColor: Colors.orange),
        );
      }
      _connectRealtime();
    }
  }

  String _moduleId(Map<String, dynamic> module) {
    return (module['module_id'] ??
            module['moduleId'] ??
            module['subject_id'] ??
            module['subjectId'] ??
            module['class_id'] ??
            module['classId'] ??
            module['id'] ??
            module['code'] ??
            '')
        .toString();
  }

  String _moduleName(Map<String, dynamic> module) {
    return (module['module_name'] ?? module['moduleName'] ?? module['subject_name'] ?? module['subjectName'] ?? module['name'] ?? 'Module').toString();
  }

  String _moduleClassName(Map<String, dynamic> module) {
    return (module['class_name'] ?? module['className'] ?? module['section'] ?? module['programme'] ?? module['department'] ?? 'Class').toString();
  }

  int _activeForModule(Map<String, dynamic> module) {
    final id = _moduleId(module);
    return _activeSessions.where((s) => s.subjectId == id || s.classId == id || s.subjectName == _moduleName(module)).length;
  }

  Future<void> _showCreateModuleSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateModuleSheet(onCreated: _load),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final teacherEmail = user?.email ?? '';

    return EnterpriseScaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(authStateProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateModuleSheet,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Create Module'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 94, 16, 110),
          children: [
            _TeacherHero(
                  name: user?.fullName ?? 'Teacher',
                  email: teacherEmail,
                  moduleCount: _modules.length,
                  activeSessions: _activeSessions.length,
                )
                .animate()
                .fadeIn(duration: 450.ms)
                .slideY(begin: 0.04),
            if (_sessionsError != null) ...[
              const SizedBox(height: 12),
              GlassCard(
                padding: const EdgeInsets.all(14),
                color: Colors.orange.withValues(alpha: 0.10),
                child: Text('Active sessions could not be refreshed: $_sessionsError'),
              ),
            ],
            const SizedBox(height: 20),
            SectionTitle(
              title: 'My Modules',
              trailing: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : null,
            ),
            const SizedBox(height: 14),
            if (_modulesError != null)
              GlassCard(
                padding: const EdgeInsets.all(18),
                color: Colors.red.withValues(alpha: 0.08),
                child: Text(_modulesError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              )
            else if (_modules.isEmpty)
              GlassCard(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.menu_book_outlined, size: 46, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 12),
                    Text('No modules for this teacher account.', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 10),
                    Text(
                      'Modules are stored in the cloud under the teacher account that created them.\n\n'
                      'Use the same teacher email on every phone (e.g. teacher@college.edu). '
                      'A newly registered teacher account starts with an empty list.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (teacherEmail.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text('Signed in as: $teacherEmail', style: Theme.of(context).textTheme.labelLarge),
                    ],
                  ],
                ),
              )
            else
              ..._modules.map((m) => _TeacherModuleCard(
                    name: _moduleName(m),
                    moduleId: _moduleId(m),
                    className: _moduleClassName(m),
                    activeSessions: _activeForModule(m),
                    onTap: () => context.push('/teacher-module', extra: m),
                  ).animate().fadeIn(duration: 360.ms).slideY(begin: 0.03)),
          ],
        ),
      ),
    );
  }
}


class _CreateModuleSheet extends StatefulWidget {
  final Future<void> Function() onCreated;

  const _CreateModuleSheet({required this.onCreated});

  @override
  State<_CreateModuleSheet> createState() => _CreateModuleSheetState();
}

class _CreateModuleSheetState extends State<_CreateModuleSheet> {
  final _moduleNameController = TextEditingController();
  final _moduleIdController = TextEditingController();
  final _passwordController = TextEditingController();
  final _classNameController = TextEditingController();
  final _departmentController = TextEditingController();
  final _sectionController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _moduleNameController.dispose();
    _moduleIdController.dispose();
    _passwordController.dispose();
    _classNameController.dispose();
    _departmentController.dispose();
    _sectionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_moduleNameController.text.trim().isEmpty ||
        _moduleIdController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Module name, Module ID, and Password are required')),
      );
      return;
    }

    setState(() => _submitting = true);
    var created = false;
    final moduleCode = _moduleIdController.text.trim().toUpperCase();

    try {
      await CatalogService().createModule(
        moduleName: _moduleNameController.text,
        moduleId: _moduleIdController.text,
        password: _passwordController.text,
        className: _classNameController.text,
        department: _departmentController.text,
        section: _sectionController.text,
      );
      created = true;
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Module $moduleCode created successfully'), backgroundColor: Colors.green),
      );
      await widget.onCreated();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create module: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted && !created) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.54,
      maxChildSize: 0.94,
      builder: (_, scrollController) {
        return GlassCard(
          radius: 32,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: ListView(
            controller: scrollController,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(Icons.add_business_outlined, color: Theme.of(context).colorScheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Create Module', style: Theme.of(context).textTheme.headlineSmall)),
                ],
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _moduleNameController,
                decoration: const InputDecoration(labelText: 'Module Name', hintText: 'Data Structures', prefixIcon: Icon(Icons.menu_book_outlined)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _moduleIdController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Module ID', hintText: 'CS101-S5-A', prefixIcon: Icon(Icons.tag_outlined)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: false,
                decoration: const InputDecoration(labelText: 'Join Password', hintText: 'Give this password only to enrolled students', prefixIcon: Icon(Icons.password_outlined)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _classNameController,
                decoration: const InputDecoration(labelText: 'Class / Section Name', hintText: 'CST-S5-A', prefixIcon: Icon(Icons.groups_outlined)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _departmentController,
                decoration: const InputDecoration(labelText: 'Department', hintText: 'Information Technology', prefixIcon: Icon(Icons.account_balance_outlined)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _sectionController,
                decoration: const InputDecoration(labelText: 'Semester / Section', hintText: 'Semester 5 • Section A', prefixIcon: Icon(Icons.badge_outlined)),
              ),
              const SizedBox(height: 18),
              AppButton(label: 'Create Module', icon: Icons.check_circle_outline, loading: _submitting, onPressed: _submit),
            ],
          ),
        );
      },
    );
  }
}

class _TeacherHero extends StatelessWidget {
  final String name;
  final String email;
  final int moduleCount;
  final int activeSessions;

  const _TeacherHero({
    required this.name,
    required this.email,
    required this.moduleCount,
    required this.activeSessions,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(22),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(gradient: LinearGradient(colors: [scheme.primary, scheme.secondary]), borderRadius: BorderRadius.circular(24)),
            child: const Icon(Icons.co_present_outlined, color: Colors.white, size: 34),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Welcome, ${name.split(' ').first}', style: Theme.of(context).textTheme.headlineSmall),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(email, style: Theme.of(context).textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    StatusPill(label: '$moduleCount Modules', icon: Icons.menu_book_outlined, color: const Color(0xFF1E4ED8)),
                    StatusPill(label: '$activeSessions Active', icon: Icons.sensors, color: const Color(0xFF10B981)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TeacherModuleCard extends StatelessWidget {
  final String name;
  final String moduleId;
  final String className;
  final int activeSessions;
  final VoidCallback onTap;

  const _TeacherModuleCard({
    required this.name,
    required this.moduleId,
    required this.className,
    required this.activeSessions,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GlassCard(
        onTap: onTap,
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(Icons.school_outlined, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: Theme.of(context).textTheme.titleLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text('$moduleId • $className', style: Theme.of(context).textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (activeSessions > 0) ...[
                    const SizedBox(height: 10),
                    StatusPill(label: '$activeSessions Live', icon: Icons.fiber_manual_record, color: const Color(0xFFEF4444)),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}
