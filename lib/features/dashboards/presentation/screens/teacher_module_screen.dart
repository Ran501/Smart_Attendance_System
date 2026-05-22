import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../services/attendance_service.dart';
import '../../../../services/catalog_service.dart';
import '../../../../services/geo_fence_service.dart';
import '../../../../widgets/app_button.dart';
import '../../../../widgets/enterprise_shell.dart';
import '../../../../widgets/session_timer.dart';

class TeacherModuleScreen extends StatefulWidget {
  final Map<String, dynamic> module;

  const TeacherModuleScreen({super.key, required this.module});

  @override
  State<TeacherModuleScreen> createState() => _TeacherModuleScreenState();
}

class _TeacherModuleScreenState extends State<TeacherModuleScreen> {
  final _attendanceService = AttendanceService();
  final _geo = GeoFenceService();

  List<Map<String, dynamic>> _sessions = [];
  List<Map<String, dynamic>> _classrooms = [];
  String? _selectedClassroom;
  int _durationMinutes = AppConstants.defaultSessionDurationMinutes;
  int _sessionUnits = 1;
  bool _gpsValidation = true;
  bool _wifiValidation = true;
  bool _bluetoothValidation = true;
  bool _loading = false;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _moduleId {
    return (widget.module['module_id'] ??
            widget.module['moduleId'] ??
            widget.module['subject_id'] ??
            widget.module['subjectId'] ??
            widget.module['class_id'] ??
            widget.module['classId'] ??
            widget.module['id'] ??
            widget.module['code'] ??
            '')
        .toString();
  }

  String get _classId {
    return (widget.module['class_id'] ?? widget.module['classId'] ?? widget.module['class'] ?? _moduleId).toString();
  }

  String get _moduleName {
    return (widget.module['module_name'] ?? widget.module['moduleName'] ?? widget.module['subject_name'] ?? widget.module['subjectName'] ?? widget.module['name'] ?? 'Module').toString();
  }

  String get _className {
    return (widget.module['class_name'] ?? widget.module['className'] ?? widget.module['section'] ?? widget.module['department'] ?? 'Class').toString();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    var sessions = <Map<String, dynamic>>[];
    var classrooms = <Map<String, dynamic>>[];
    String? sessionError;

    try {
      sessions = await _attendanceService.getModuleSessions(moduleId: _moduleId);
    } catch (e) {
      sessionError = e.toString().replaceFirst('Exception: ', '');
    }

    try {
      classrooms = await CatalogService().getClassrooms(classId: _classId);
    } catch (_) {
      classrooms = <Map<String, dynamic>>[];
    }

    if (mounted) {
      setState(() {
        _sessions = sessions;
        _classrooms = classrooms;
        if (_selectedClassroom == null && _classrooms.isNotEmpty) {
          _selectedClassroom = (_classrooms.first['id'] ?? _classrooms.first['classroom_id'] ?? _classrooms.first['classroomId'])?.toString();
        }
        _loading = false;
      });
      if (sessionError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load sessions: $sessionError'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _startSession() async {
    if (_selectedClassroom == null || _selectedClassroom!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a classroom first')));
      return;
    }
    setState(() => _starting = true);
    try {
      final position = await _geo.getBestPosition();
      if (position == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enable GPS and wait for a fix before starting'), backgroundColor: Colors.orange));
        }
        return;
      }

      final session = await _attendanceService.createSession(
        classId: _classId,
        subjectId: _moduleId,
        classroomId: _selectedClassroom!,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        durationMinutes: _durationMinutes,
        radiusMeters: AppConstants.hostSessionBaseRadiusMeters.toInt(),
        sessionUnits: _sessionUnits,
      );
      if (mounted) {
        final extra = {
          'id': session.id,
          'sessionId': session.id,
          'subject_id': _moduleId,
          'subject_name': _moduleName,
          'class_id': _classId,
          'class_name': _className,
          'ends_at': session.endsAt.toIso8601String(),
          'session_units': _sessionUnits,
          'sessionUnits': _sessionUnits,
        };
        await _load();
        if (mounted) context.push('/session/${session.id}', extra: extra);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  String _sessionId(Map<String, dynamic> s) => (s['id'] ?? s['session_id'] ?? s['sessionId'] ?? '').toString();

  String _sessionModuleName(Map<String, dynamic> s) {
    return (s['subject_name'] ?? s['subjectName'] ?? s['module_name'] ?? s['moduleName'] ?? _moduleName).toString();
  }

  String _sessionClassName(Map<String, dynamic> s) {
    return (s['class_name'] ?? s['className'] ?? s['class_id'] ?? s['classId'] ?? _className).toString();
  }

  int _unitsOf(Map<String, dynamic> s) => _attendanceService.sessionUnitsOf(s);

  int get _totalSessionUnits => _sessions.fold<int>(0, (sum, s) => sum + _unitsOf(s));

  int _num(Map<String, dynamic> s, List<String> keys) {
    for (final key in keys) {
      final raw = s[key];
      if (raw is num) return raw.toInt();
      final parsed = int.tryParse(raw?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return 0;
  }

  String _statusOf(Map<String, dynamic> record) {
    final raw = (record['status'] ?? record['attendance_status'] ?? record['attendanceStatus'] ?? '').toString().trim().toUpperCase();
    if (raw.isEmpty || raw == 'NULL') return 'ABSENT';
    if (raw == 'MEDICAL' || raw == 'MEDICAL LEAVE' || raw == 'ML') return 'MEDICAL_LEAVE';
    if (raw == 'OFFICIAL' || raw == 'OFFICIAL LEAVE' || raw == 'OL') return 'OFFICIAL_LEAVE';
    return raw;
  }

  String _studentName(Map<String, dynamic> m) {
    return (m['full_name'] ?? m['student_name'] ?? m['studentName'] ?? m['name'] ?? m['user_name'] ?? m['email'] ?? 'Student').toString();
  }

  String _studentId(Map<String, dynamic> m) {
    return (m['student_id'] ?? m['studentId'] ?? m['student_code'] ?? m['studentCode'] ?? m['user_id'] ?? m['userId'] ?? m['cid'] ?? _studentName(m)).toString();
  }

  Future<List<_StudentSummary>> _buildStudentSummaries() async {
    final summary = <String, _StudentSummary>{};
    for (final session in _sessions) {
      final sessionId = _sessionId(session);
      if (sessionId.isEmpty) continue;
      final units = _unitsOf(session);
      final records = await _attendanceService.getSessionRoster(sessionId);
      for (final record in records) {
        final studentId = _studentId(record);
        final student = summary.putIfAbsent(studentId, () => _StudentSummary(id: studentId, name: _studentName(record)));
        student.totalUnits += units;
        switch (_statusOf(record)) {
          case 'PRESENT':
            student.presentUnits += units;
            break;
          case 'MEDICAL_LEAVE':
            student.medicalUnits += units;
            break;
          case 'OFFICIAL_LEAVE':
            student.officialUnits += units;
            break;
          default:
            student.absentUnits += units;
        }
      }
    }
    final rows = summary.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return rows;
  }

  Future<void> _showSummarySheet() async {
    if (_sessions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No sessions found for this module')));
      return;
    }
    setState(() => _loading = true);
    try {
      final rows = await _buildStudentSummaries();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) {
          return DraggableScrollableSheet(
            initialChildSize: 0.88,
            minChildSize: 0.50,
            maxChildSize: 0.95,
            builder: (_, scrollController) {
              return GlassCard(
                radius: 30,
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text('Attendance Summary', style: Theme.of(context).textTheme.headlineSmall)),
                        IconButton(icon: const Icon(Icons.print_outlined), onPressed: () => _printSummary(rows)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        StatusPill(label: '${_sessions.length} Records', icon: Icons.event_note_outlined, color: const Color(0xFF1E4ED8)),
                        StatusPill(label: '$_totalSessionUnits Counted Sessions', icon: Icons.calculate_outlined, color: const Color(0xFF10B981)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: rows.isEmpty
                          ? const Center(child: Text('No student records returned by backend roster endpoint.'))
                          : SingleChildScrollView(
                              controller: scrollController,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  columns: const [
                                    DataColumn(label: Text('Student')),
                                    DataColumn(label: Text('ID')),
                                    DataColumn(label: Text('Present')),
                                    DataColumn(label: Text('Absent')),
                                    DataColumn(label: Text('Medical')),
                                    DataColumn(label: Text('Official')),
                                    DataColumn(label: Text('Present %')),
                                    DataColumn(label: Text('Absent Rule')),
                                    DataColumn(label: Text('Leave Rule')),
                                    DataColumn(label: Text('Status')),
                                  ],
                                  rows: rows.map((r) {
                                    final color = r.isSafe ? const Color(0xFF10B981) : const Color(0xFFEF4444);
                                    return DataRow(cells: [
                                      DataCell(Text(r.name)),
                                      DataCell(Text(r.id)),
                                      DataCell(Text('${r.presentUnits}')),
                                      DataCell(Text('${r.absentUnits}')),
                                      DataCell(Text('${r.medicalUnits}')),
                                      DataCell(Text('${r.officialUnits}')),
                                      DataCell(Text('${r.presentPercentage.toStringAsFixed(1)}%')),
                                      DataCell(Text('${r.absentRulePercentage.toStringAsFixed(1)}%')),
                                      DataCell(Text('${r.leaveRulePercentage.toStringAsFixed(1)}%')),
                                      DataCell(Text(r.statusLabel, style: TextStyle(color: color, fontWeight: FontWeight.w800))),
                                    ]);
                                  }).toList(),
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(height: 12),
                    AppButton(label: 'Print Summary Report', icon: Icons.print_outlined, onPressed: () => _printSummary(rows)),
                  ],
                ),
              );
            },
          );
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not build summary: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _printSummary(List<_StudentSummary> rows) async {
    final pdf = pw.Document();
    final now = DateTime.now();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (_) => [
          pw.Text('FacePass Bhutan - Attendance Summary', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text('Module: $_moduleName ($_moduleId)'),
          pw.Text('Class: $_className'),
          pw.Text('Generated: ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}'),
          pw.Text('Manual rule: Absent-only percentage must be at least 90%. Absent + medical + official leave percentage must keep leave-rule percentage at least 80%.'),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: ['Student', 'ID', 'Total', 'Present', 'Absent', 'Medical', 'Official', 'Present %', 'Absent Rule', 'Leave Rule', 'Status'],
            data: rows
                .map((r) => [
                      r.name,
                      r.id,
                      '${r.totalUnits}',
                      '${r.presentUnits}',
                      '${r.absentUnits}',
                      '${r.medicalUnits}',
                      '${r.officialUnits}',
                      '${r.presentPercentage.toStringAsFixed(1)}%',
                      '${r.absentRulePercentage.toStringAsFixed(1)}%',
                      '${r.leaveRulePercentage.toStringAsFixed(1)}%',
                      r.statusLabel,
                    ])
                .toList(),
          ),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (_) async => pdf.save());
  }



  void _openSession(Map<String, dynamic> s) {
    final id = _sessionId(s);
    if (id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session ID not found')));
      return;
    }
    context.push('/session/$id', extra: {
      ...s,
      'subject_id': _moduleId,
      'subject_name': _moduleName,
      'class_id': _classId,
      'class_name': _className,
      'session_units': _unitsOf(s),
    });
  }

  Future<void> _showModuleAnalyticsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.86,
          minChildSize: 0.48,
          maxChildSize: 0.95,
          builder: (_, scrollController) {
            return GlassCard(
              radius: 30,
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              child: ListView(
                controller: scrollController,
                children: [
                  Center(
                    child: Container(
                      width: 46,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(999),
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
                        child: Icon(Icons.analytics_outlined, color: Theme.of(context).colorScheme.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Module Analytics', style: Theme.of(context).textTheme.headlineSmall),
                            const SizedBox(height: 3),
                            Text(_moduleName, style: Theme.of(context).textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(sheetContext).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      StatusPill(label: '${_sessions.length} Session Records', icon: Icons.event_note_outlined, color: const Color(0xFF1E4ED8)),
                      StatusPill(label: '$_totalSessionUnits Counted Sessions', icon: Icons.calculate_outlined, color: const Color(0xFF10B981)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_loading)
                    const Center(child: Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator()))
                  else if (_sessions.isEmpty)
                    const GlassCard(
                      child: ListTile(
                        leading: Icon(Icons.analytics_outlined),
                        title: Text('No sessions yet for this module'),
                      ),
                    )
                  else
                    ..._sessions.map((s) => _ModuleSessionCard(
                          session: s,
                          sessionId: _sessionId(s),
                          subject: _sessionModuleName(s),
                          className: _sessionClassName(s),
                          units: _unitsOf(s),
                          present: _num(s, const ['present', 'present_count', 'presentCount']),
                          rejected: _num(s, const ['rejected', 'rejected_count', 'rejectedCount']),
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            _openSession(s);
                          },
                        )),
                  const SizedBox(height: 14),
                  AppButton(
                    label: 'Summary / Print Report',
                    icon: Icons.table_chart_outlined,
                    onPressed: _loading
                        ? null
                        : () {
                            Navigator.of(sheetContext).pop();
                            Future<void>.delayed(const Duration(milliseconds: 120), () {
                              if (mounted) _showSummarySheet();
                            });
                          },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return EnterpriseScaffold(
      appBar: AppBar(
        title: Text(_moduleName),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        actions: [
          IconButton(
            tooltip: 'Module analytics',
            icon: const Icon(Icons.analytics_outlined),
            onPressed: _showModuleAnalyticsSheet,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 94, 16, 36),
          children: [
            GlassCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_moduleName, style: Theme.of(context).textTheme.headlineSmall),
                            const SizedBox(height: 4),
                            Text('$_moduleId • $_className', style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                      StatusPill(label: '${_sessions.length} Sessions', icon: Icons.event_note_outlined, color: const Color(0xFF1E4ED8)),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const SectionTitle(title: 'Start Attendance Session'),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _selectedClassroom,
                    decoration: const InputDecoration(labelText: 'Classroom', prefixIcon: Icon(Icons.location_city_outlined)),
                    items: _classrooms
                        .map((c) => DropdownMenuItem(
                              value: (c['id'] ?? c['classroom_id'] ?? c['classroomId']).toString(),
                              child: Text((c['name'] ?? c['room_name'] ?? c['classroomName'] ?? 'Room').toString()),
                            ))
                        .toList(),
                    onChanged: _starting ? null : (v) => setState(() => _selectedClassroom = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: _sessionUnits,
                    decoration: const InputDecoration(labelText: 'Count this attendance as', prefixIcon: Icon(Icons.view_timeline_outlined)),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('1 Session')),
                      DropdownMenuItem(value: 2, child: Text('2 Sessions / Double period')),
                      DropdownMenuItem(value: 3, child: Text('3 Sessions / Block period')),
                    ],
                    onChanged: _starting ? null : (v) => setState(() => _sessionUnits = v ?? 1),
                  ),
                  const SizedBox(height: 12),
                  Text('Session duration: $_durationMinutes minutes', style: Theme.of(context).textTheme.titleSmall),
                  Slider(
                    value: _durationMinutes.toDouble(),
                    min: 3,
                    max: 30,
                    divisions: 27,
                    label: '$_durationMinutes min',
                    onChanged: _starting ? null : (v) => setState(() => _durationMinutes = v.round()),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _ValidationChip(label: 'GPS', value: _gpsValidation, icon: Icons.my_location, onChanged: (v) => setState(() => _gpsValidation = v)),
                      _ValidationChip(label: 'WiFi', value: _wifiValidation, icon: Icons.wifi, onChanged: (v) => setState(() => _wifiValidation = v)),
                      _ValidationChip(label: 'BLE', value: _bluetoothValidation, icon: Icons.bluetooth, onChanged: (v) => setState(() => _bluetoothValidation = v)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  AppButton(label: 'Start Session', icon: Icons.play_arrow_rounded, loading: _starting, onPressed: _startSession),
                ],
              ),
            ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.04),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _ValidationChip extends StatelessWidget {
  final String label;
  final bool value;
  final IconData icon;
  final ValueChanged<bool> onChanged;

  const _ValidationChip({required this.label, required this.value, required this.icon, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final color = value ? const Color(0xFF10B981) : Theme.of(context).colorScheme.outline;
    return FilterChip(selected: value, onSelected: onChanged, avatar: Icon(icon, size: 18, color: color), label: Text(label));
  }
}

class _ModuleSessionCard extends StatelessWidget {
  final Map<String, dynamic> session;
  final String sessionId;
  final String subject;
  final String className;
  final int units;
  final int present;
  final int rejected;
  final VoidCallback onTap;

  const _ModuleSessionCard({
    required this.session,
    required this.sessionId,
    required this.subject,
    required this.className,
    required this.units,
    required this.present,
    required this.rejected,
    required this.onTap,
  });

  DateTime? _endsAt() {
    final raw = session['ends_at'] ?? session['endsAt'];
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final endsAt = _endsAt();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        onTap: onTap,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(sessionId, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text('$subject • $className', style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      StatusPill(label: 'Present: $present', icon: Icons.check_circle_outline, color: const Color(0xFF10B981)),
                      StatusPill(label: 'Rejected: $rejected', icon: Icons.gpp_bad_outlined, color: const Color(0xFFEF4444)),
                      StatusPill(label: 'Counts: $units', icon: Icons.calculate_outlined, color: const Color(0xFF8B5CF6)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (endsAt != null) SessionTimer(endsAt: endsAt) else const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class _StudentSummary {
  final String id;
  final String name;
  int totalUnits = 0;
  int presentUnits = 0;
  int absentUnits = 0;
  int medicalUnits = 0;
  int officialUnits = 0;

  _StudentSummary({required this.id, required this.name});

  double get presentPercentage => totalUnits == 0 ? 0 : (presentUnits / totalUnits) * 100;
  double get absentRulePercentage => totalUnits == 0 ? 0 : 100 - ((absentUnits / totalUnits) * 100);
  double get leaveRulePercentage => totalUnits == 0 ? 0 : 100 - (((absentUnits + medicalUnits + officialUnits) / totalUnits) * 100);
  bool get isSafe => absentRulePercentage >= 90 && leaveRulePercentage >= 80;
  String get statusLabel {
    if (isSafe) return 'Safe';
    if (absentRulePercentage < 90) return 'Absent > 10%';
    return 'Leave + Absent > 20%';
  }
}
