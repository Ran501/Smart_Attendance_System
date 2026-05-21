import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../models/attendance_session_model.dart';
import '../../../../services/attendance_service.dart';
import '../../../../services/catalog_service.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../services/geo_fence_service.dart';
import '../../../../widgets/app_button.dart';
import '../../../../widgets/session_timer.dart';

class TeacherDashboardScreen extends ConsumerStatefulWidget {
  const TeacherDashboardScreen({super.key});

  @override
  ConsumerState<TeacherDashboardScreen> createState() => _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState extends ConsumerState<TeacherDashboardScreen> {
  List<AttendanceSessionModel> _sessions = [];
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _subjects = [];
  List<Map<String, dynamic>> _classrooms = [];
  String? _selectedClass;
  String? _selectedSubject;
  String? _selectedClassroom;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final catalog = CatalogService();
      final sessions = await AttendanceService().getActiveSessions();
      final classes = await catalog.getClasses();
      if (mounted) {
        setState(() {
          _sessions = sessions;
          _classes = classes;
          if (_selectedClass == null && classes.isNotEmpty) {
            _selectedClass = classes.first['id'] as String?;
          }
        });
        if (_selectedClass != null) await _loadSubjects();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadSubjects() async {
    final subjects = await CatalogService().getSubjects(classId: _selectedClass);
    final classrooms = await CatalogService().getClassrooms(classId: _selectedClass);
    if (mounted) {
      setState(() {
        _subjects = subjects;
        _classrooms = classrooms;
        _selectedSubject = subjects.isNotEmpty ? subjects.first['id'] as String? : null;
        _selectedClassroom = classrooms.isNotEmpty ? classrooms.first['id'] as String? : null;
      });
    }
  }

  Future<void> _startSession() async {
    if (_selectedClass == null || _selectedSubject == null || _selectedClassroom == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select class, subject, and classroom')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final position = await GeoFenceService().getBestPosition();
      if (position == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Enable GPS and wait for a fix before starting (try near a window)',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final session = await AttendanceService().createSession(
        classId: _selectedClass!,
        subjectId: _selectedSubject!,
        classroomId: _selectedClassroom!,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        radiusMeters: AppConstants.hostSessionBaseRadiusMeters.toInt(),
      );
      if (mounted) {
        context.push('/session/${session.id}', extra: session);
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Teacher Dashboard'),
        actions: [
          IconButton(icon: const Icon(Icons.analytics), onPressed: () => context.push('/analytics')),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(authStateProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: _loading && _sessions.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('Start Attendance Session', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _selectedClass,
                    decoration: const InputDecoration(labelText: 'Class'),
                    items: _classes
                        .map((c) => DropdownMenuItem(
                              value: c['id'] as String,
                              child: Text(c['name'] as String? ?? c['id'] as String),
                            ))
                        .toList(),
                    onChanged: (v) async {
                      setState(() => _selectedClass = v);
                      await _loadSubjects();
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _selectedSubject,
                    decoration: const InputDecoration(labelText: 'Subject'),
                    items: _subjects
                        .map((s) => DropdownMenuItem(
                              value: s['id'] as String,
                              child: Text(s['name'] as String? ?? ''),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedSubject = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _selectedClassroom,
                    decoration: const InputDecoration(labelText: 'Classroom (Geo + WiFi)'),
                    items: _classrooms
                        .map((c) => DropdownMenuItem(
                              value: c['id'] as String,
                              child: Text(c['name'] as String? ?? 'Room'),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedClassroom = v),
                  ),
                  const SizedBox(height: 20),
                  AppButton(
                    label: 'Start Session (5 min • near you)',
                    icon: Icons.play_arrow,
                    loading: _loading,
                    onPressed: _startSession,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your GPS anchors the session. Students nearby can mark attendance (GPS buffer applied). '
                    'Use class "Computer Science S5 A" (CST-S5-A) so enrolled students see it.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 32),
                  Text('Active Sessions', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  if (_sessions.isEmpty)
                    const Card(child: ListTile(title: Text('No active sessions'))),
                  ..._sessions.map((s) => Card(
                        child: ListTile(
                          title: Text(s.id),
                          subtitle: Text('${s.className ?? s.classId} • ${s.subjectName ?? ''}'),
                          trailing: SessionTimer(endsAt: s.endsAt),
                          onTap: () => context.push('/session/${s.id}', extra: s),
                        ),
                      )),
                ],
              ),
            ),
    );
  }
}
