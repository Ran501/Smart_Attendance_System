import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../services/attendance_service.dart';
import '../../../../services/catalog_service.dart';
import '../../../../services/realtime_socket.dart';
import '../../../../services/teacher_ble_beacon_service.dart';
import '../../../../widgets/app_button.dart';
import '../../../../services/notification_service.dart';
import '../../../../widgets/enterprise_shell.dart';
import '../../../../widgets/session_timer.dart';
import '../../../notifications/notification_screen.dart';

class TeacherModuleScreen extends StatefulWidget {
  final Map<String, dynamic> module;

  const TeacherModuleScreen({super.key, required this.module});

  @override
  State<TeacherModuleScreen> createState() => _TeacherModuleScreenState();
}

class _TeacherModuleScreenState extends State<TeacherModuleScreen> {
  static const int _sessionsPerReportPage = 15;

  final _attendanceService = AttendanceService();
  final _catalog = CatalogService();
  final _semesterHoursController = TextEditingController();
  final _hoursPerWeekController = TextEditingController();

  List<Map<String, dynamic>> _sessions = [];
  Map<String, dynamic>? _attendancePlan;
  String? _moduleClassroomId;
  String _moduleClassroomName = '';
  int _durationMinutes = AppConstants.defaultSessionDurationMinutes;
  int _sessionUnits = 1;
  bool _loading = false;
  bool _starting = false;
  bool _planSaving = false;
  bool _planExpanded = true;
  final _realtime = RealtimeAttendanceSocket();
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
    unreadCountNotifier.refresh();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && !_loading && !_starting) _loadQuiet();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _realtime.disconnect();
    _semesterHoursController.dispose();
    _hoursPerWeekController.dispose();
    super.dispose();
  }

  void _connectRealtime() {
    _realtime.connect(
      classIds: [_classId],
      onDataChanged: () {
        if (mounted) _loadQuiet();
      },
    );
  }

  Future<void> _loadQuiet() async {
    try {
      final results = await Future.wait([
        _attendanceService.getModuleSessions(moduleId: _moduleId),
        _catalog.getAttendancePlan(_moduleId),
      ]);
      if (mounted) {
        setState(() {
          _sessions = List<Map<String, dynamic>>.from(results[0] as List);
          _attendancePlan = results[1] as Map<String, dynamic>;
        });
        _syncPlanControllers();
      }
    } catch (_) {}
  }

  void _syncPlanControllers() {
    final plan = _attendancePlan;
    if (plan == null) return;
    final semester = plan['semesterTotalHours'] ?? plan['semester_total_hours'];
    final perWeek = plan['hoursPerWeek'] ?? plan['hours_per_week'];
    if (semester != null && _semesterHoursController.text.isEmpty) {
      _semesterHoursController.text = semester.toString();
    }
    if (perWeek != null && _hoursPerWeekController.text.isEmpty) {
      _hoursPerWeekController.text = perWeek.toString();
    }
  }

  List<Map<String, dynamic>> get _atRiskStudents {
    final raw = _attendancePlan?['atRiskStudents'] ?? _attendancePlan?['at_risk_students'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }

  int get _maxAllowedAbsences {
    final v = _attendancePlan?['maxAllowedAbsences'] ?? _attendancePlan?['max_allowed_absences'];
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  Future<void> _loadAttendancePlan() async {
    try {
      final plan = await _catalog.getAttendancePlan(_moduleId);
      if (!mounted) return;
      setState(() => _attendancePlan = plan);
      final semester = plan['semesterTotalHours'] ?? plan['semester_total_hours'];
      final perWeek = plan['hoursPerWeek'] ?? plan['hours_per_week'];
      if (semester != null) _semesterHoursController.text = semester.toString();
      if (perWeek != null) _hoursPerWeekController.text = perWeek.toString();
    } catch (_) {
      if (mounted) setState(() => _attendancePlan = null);
    }
  }

  Future<void> _saveAttendancePlan() async {
    final semester = int.tryParse(_semesterHoursController.text.trim());
    final perWeek = double.tryParse(_hoursPerWeekController.text.trim());
    if (semester == null || semester < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter total semester hours (at least 1)')),
      );
      return;
    }
    if (perWeek == null || perWeek <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter hours per week (greater than 0)')),
      );
      return;
    }

    setState(() => _planSaving = true);
    try {
      final plan = await _catalog.updateAttendancePlan(
        moduleId: _moduleId,
        semesterTotalHours: semester,
        hoursPerWeek: perWeek,
      );
      if (mounted) {
        setState(() => _attendancePlan = plan);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Plan saved — max ${plan['maxAllowedAbsences'] ?? plan['max_allowed_absences']} absences allowed (90% rule)',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save plan: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _planSaving = false);
    }
  }

  Future<void> _recordPlanAdjustment({required int extra, required int cancelled}) async {
    if (extra == 0 && cancelled == 0) return;
    setState(() => _planSaving = true);
    try {
      final plan = await _catalog.recordAttendancePlanAdjustment(
        moduleId: _moduleId,
        extraClasses: extra,
        cancelledClasses: cancelled,
      );
      if (mounted) {
        setState(() => _attendancePlan = plan);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Class adjustment recorded — max absences unchanged')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Adjustment failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _planSaving = false);
    }
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
    String? sessionError;
    String? classroomId;
    var classroomName = _className;

    try {
      sessions = await _attendanceService.getModuleSessions(moduleId: _moduleId);
    } catch (e) {
      sessionError = e.toString().replaceFirst('Exception: ', '');
    }

    await _loadAttendancePlan();

    try {
      final classrooms = await CatalogService().getClassrooms(classId: _classId);
      if (classrooms.isNotEmpty) {
        final room = classrooms.first;
        classroomId = (room['id'] ?? room['classroom_id'] ?? room['classroomId'])?.toString();
        classroomName = (room['name'] ?? room['room_name'] ?? room['classroomName'] ?? _className).toString();
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _sessions = sessions;
        _moduleClassroomId = classroomId;
        _moduleClassroomName = classroomName;
        _loading = false;
      });
      if (sessionError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load sessions: $sessionError'), backgroundColor: Colors.red),
        );
      }
      _connectRealtime();
    }
  }

  Future<void> _startSession() async {
    if (_moduleClassroomId == null || _moduleClassroomId!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No classroom linked to this module yet')),
      );
      return;
    }
    setState(() => _starting = true);
    try {
      final session = await _attendanceService.createSession(
        classId: _classId,
        subjectId: _moduleId,
        classroomId: _moduleClassroomId!,
        durationMinutes: _durationMinutes,
        sessionUnits: _sessionUnits,
      );
      final beacon = await TeacherBleBeaconService.instance.start(session.id);
      if (mounted && !beacon.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(beacon.message),
            backgroundColor: Colors.orange,
            action: beacon.openSettings
                ? SnackBarAction(
                    label: 'Settings',
                    onPressed: () => TeacherBleBeaconService.instance.openAppSettings(),
                  )
                : null,
          ),
        );
      }
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

  DateTime _sessionStartedAt(Map<String, dynamic> session) {
    final raw = session['started_at'] ?? session['startedAt'] ?? session['created_at'] ?? session['createdAt'];
    return DateTime.tryParse(raw?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _sessionHeaderLabel(Map<String, dynamic> session) {
    final dt = _sessionStartedAt(session);
    final date = DateFormat('dd/MM/yyyy').format(dt);
    final time = DateFormat('hh:mm a').format(dt);
    final hours = _unitsOf(session);
    return '$date\n$time\n${hours}h';
  }

  List<List<_SessionColumn>> _sessionPages(List<_SessionColumn> sessions) {
    if (sessions.isEmpty) return [[]];
    final pages = <List<_SessionColumn>>[];
    for (var i = 0; i < sessions.length; i += _sessionsPerReportPage) {
      final end = (i + _sessionsPerReportPage > sessions.length)
          ? sessions.length
          : i + _sessionsPerReportPage;
      pages.add(sessions.sublist(i, end));
    }
    return pages;
  }

  Widget _statusMark(String status) {
    switch (status) {
      case 'PRESENT':
      case 'LATE':
        return const Text('P', style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.w900, fontSize: 16));
      case 'MEDICAL_LEAVE':
        return const Text('ML', style: TextStyle(color: Color(0xFFF97316), fontWeight: FontWeight.w800));
      case 'OFFICIAL_LEAVE':
        return const Text('OL', style: TextStyle(color: Color(0xFFF97316), fontWeight: FontWeight.w800));
      default:
        return const Text('A', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w900));
    }
  }

  pw.Widget _pdfStatusMark(String status) {
    switch (status) {
      case 'PRESENT':
      case 'LATE':
        return pw.Text('P', style: pw.TextStyle(color: PdfColors.green, fontWeight: pw.FontWeight.bold, fontSize: 10));
      case 'MEDICAL_LEAVE':
        return pw.Text('ML', style: pw.TextStyle(color: PdfColors.orange, fontWeight: pw.FontWeight.bold, fontSize: 9));
      case 'OFFICIAL_LEAVE':
        return pw.Text('OL', style: pw.TextStyle(color: PdfColors.orange, fontWeight: pw.FontWeight.bold, fontSize: 9));
      default:
        return pw.Text('A', style: pw.TextStyle(color: PdfColors.red, fontWeight: pw.FontWeight.bold, fontSize: 10));
    }
  }

  Future<_ModuleReport> _buildModuleReport() async {
    final sortedSessions = List<Map<String, dynamic>>.from(_sessions)
      ..sort((a, b) => _sessionStartedAt(a).compareTo(_sessionStartedAt(b)));

    final sessionColumns = sortedSessions
        .map(
          (s) => _SessionColumn(
            id: _sessionId(s),
            header: _sessionHeaderLabel(s),
            units: _unitsOf(s),
          ),
        )
        .where((s) => s.id.isNotEmpty)
        .toList();

    final students = <String, _StudentReportRow>{};

    for (final session in sortedSessions) {
      final sessionId = _sessionId(session);
      if (sessionId.isEmpty) continue;
      final units = _unitsOf(session);
      final records = await _attendanceService.getSessionRoster(sessionId);
      for (final record in records) {
        final studentId = _studentId(record);
        final row = students.putIfAbsent(
          studentId,
          () => _StudentReportRow(id: studentId, name: _studentName(record)),
        );
        row.applySession(sessionId, _statusOf(record), units);
      }
    }

  // Mark absent for students missing from a session roster.
    for (final session in sessionColumns) {
      for (final row in students.values) {
        row.ensureSession(session.id, session.units);
      }
    }

    final rows = students.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    for (var i = 0; i < rows.length; i++) {
      rows[i].slNo = i + 1;
    }

    return _ModuleReport(sessions: sessionColumns, rows: rows);
  }

  Future<void> _showSummarySheet() async {
    if (_sessions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No sessions found for this module')));
      return;
    }
    setState(() => _loading = true);
    try {
      final report = await _buildModuleReport();
      if (!mounted) return;
      final sessionPages = _sessionPages(report.sessions);
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
                            IconButton(icon: const Icon(Icons.print_outlined), onPressed: () => _printSummary(report)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        StatusPill(
                          label: '${report.sessions.length} Sessions • ${sessionPages.length} page(s)',
                          icon: Icons.event_note_outlined,
                          color: const Color(0xFF1E4ED8),
                        ),
                        const SizedBox(height: 14),
                        Expanded(
                          child: report.rows.isEmpty
                              ? const Center(child: Text('No student records returned by backend roster endpoint.'))
                              : PageView.builder(
                                  itemCount: sessionPages.length,
                                  itemBuilder: (_, pageIndex) {
                                    final chunk = sessionPages[pageIndex];
                                    final isLastPage = pageIndex == sessionPages.length - 1;
                                    return SingleChildScrollView(
                                      controller: scrollController,
                                      child: SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: DataTable(
                                          columns: [
                                            const DataColumn(label: Text('Sl')),
                                            const DataColumn(label: Text('Name')),
                                            const DataColumn(label: Text('ID')),
                                            ...chunk.map(
                                              (s) => DataColumn(
                                                label: Text(s.header, textAlign: TextAlign.center),
                                              ),
                                            ),
                                            if (isLastPage) ...[
                                              const DataColumn(label: Text('Rule 1')),
                                              const DataColumn(label: Text('Rule 2')),
                                            ],
                                          ],
                                          rows: report.rows.map((r) {
                                            return DataRow(
                                              cells: [
                                                DataCell(Text('${r.slNo}')),
                                                DataCell(Text(r.name)),
                                                DataCell(Text(r.id)),
                                                ...chunk.map(
                                                  (s) => DataCell(
                                                    Center(child: _statusMark(r.statusFor(s.id))),
                                                  ),
                                                ),
                                                if (isLastPage) ...[
                                                  DataCell(Text('${r.rule1Percentage.toStringAsFixed(1)}%')),
                                                  DataCell(Text('${r.rule2Percentage.toStringAsFixed(1)}%')),
                                                ],
                                              ],
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                        const SizedBox(height: 12),
                        AppButton(label: 'Print Summary Report', icon: Icons.print_outlined, onPressed: () => _printSummary(report)),
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

  List<pw.TableRow> _pdfTableRows(
    _ModuleReport report,
    List<_SessionColumn> sessionChunk, {
    required bool includeRules,
  }) {
    final headerStyle = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);
    final cellStyle = const pw.TextStyle(fontSize: 8);

    pw.Widget cell(String text, {pw.TextStyle? style, pw.TextAlign align = pw.TextAlign.center}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.all(3),
        child: pw.Text(text, style: style ?? cellStyle, textAlign: align),
      );
    }

    return [
      pw.TableRow(
        children: [
          cell('Sl', style: headerStyle),
          cell('Name', style: headerStyle, align: pw.TextAlign.left),
          cell('ID', style: headerStyle),
          ...sessionChunk.map((s) => cell(s.header, style: headerStyle)),
          if (includeRules) ...[
            cell('Rule 1', style: headerStyle),
            cell('Rule 2', style: headerStyle),
          ],
        ],
      ),
      ...report.rows.map(
        (r) => pw.TableRow(
          children: [
            cell('${r.slNo}'),
            pw.Padding(
              padding: const pw.EdgeInsets.all(3),
              child: pw.Text(r.name, style: cellStyle),
            ),
            cell(r.id),
            ...sessionChunk.map(
              (s) => pw.Padding(
                padding: const pw.EdgeInsets.all(3),
                child: pw.Center(child: _pdfStatusMark(r.statusFor(s.id))),
              ),
            ),
            if (includeRules) ...[
              cell('${r.rule1Percentage.toStringAsFixed(1)}%'),
              cell('${r.rule2Percentage.toStringAsFixed(1)}%'),
            ],
          ],
        ),
      ),
    ];
  }

  Future<void> _printSummary(_ModuleReport report) async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final sessionPages = _sessionPages(report.sessions);
    final titleStyle = pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold);
    final metaStyle = const pw.TextStyle(fontSize: 9);

    for (var pageIndex = 0; pageIndex < sessionPages.length; pageIndex++) {
      final chunk = sessionPages[pageIndex];
      final isLastPage = pageIndex == sessionPages.length - 1;
      final tableRows = _pdfTableRows(report, chunk, includeRules: isLastPage);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('FacePass Bhutan - Attendance Summary', style: titleStyle),
                pw.SizedBox(height: 4),
                pw.Text('Module: $_moduleName ($_moduleId)', style: metaStyle),
                pw.Text('Class: $_className • Classroom: $_moduleClassroomName', style: metaStyle),
                pw.Text(
                  'Generated: ${DateFormat('dd/MM/yyyy hh:mm a').format(now)} • Page ${pageIndex + 1}/${sessionPages.length}',
                  style: metaStyle,
                ),
                pw.SizedBox(height: 8),
                pw.Expanded(
                  child: pw.Table(
                    border: pw.TableBorder.all(width: 0.4, color: PdfColors.grey600),
                    defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
                    children: tableRows,
                  ),
                ),
              ],
            );
          },
        ),
      );
    }

    if (sessionPages.isEmpty) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          build: (_) => pw.Center(child: pw.Text('No sessions for this module')),
        ),
      );
    }

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
          ValueListenableBuilder<int>(
            valueListenable: unreadCountNotifier,
            builder: (context, count, _) => Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  tooltip: 'Notifications',
                  icon: const Icon(Icons.notifications_none_rounded),
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const NotificationScreen())),
                ),
                if (count > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        count > 99 ? '99+' : '$count',
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          ),
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
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Classroom',
                      prefixIcon: Icon(Icons.location_city_outlined),
                    ),
                    child: Text(
                      _moduleClassroomName.isEmpty ? _className : _moduleClassroomName,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    initialValue: _sessionUnits,
                    decoration: const InputDecoration(
                      labelText: 'Session length (hours)',
                      prefixIcon: Icon(Icons.view_timeline_outlined),
                      helperText: '1 session = 1 hour • 2 sessions = 2 hours • 3 sessions = 3 hours',
                    ),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('1 Session (1 hour)')),
                      DropdownMenuItem(value: 2, child: Text('2 Sessions / Double period (2 hours)')),
                      DropdownMenuItem(value: 3, child: Text('3 Sessions / Block period (3 hours)')),
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
                  Text(
                    'Students mark attendance using face verification and must be within ${AppConstants.bleMaxDistanceMeters.toInt()} m of your phone via Bluetooth.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  AppButton(label: 'Start Session', icon: Icons.play_arrow_rounded, loading: _starting, onPressed: _startSession),
                ],
              ),
            ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.04),
            const SizedBox(height: 16),
            _AttendancePlanCard(
              expanded: _planExpanded,
              onToggle: () => setState(() => _planExpanded = !_planExpanded),
              semesterController: _semesterHoursController,
              hoursPerWeekController: _hoursPerWeekController,
              plan: _attendancePlan,
              maxAllowedAbsences: _maxAllowedAbsences,
              saving: _planSaving,
              onSave: _saveAttendancePlan,
              onExtraClass: () => _recordPlanAdjustment(extra: 1, cancelled: 0),
              onCancelledClass: () => _recordPlanAdjustment(extra: 0, cancelled: 1),
            ).animate().fadeIn(delay: 80.ms, duration: 400.ms).slideY(begin: 0.04),
            const SizedBox(height: 16),
            _AtRiskStudentsCard(
              moduleName: _moduleName,
              students: _atRiskStudents,
              configured: _attendancePlan?['configured'] == true || _maxAllowedAbsences > 0,
            ).animate().fadeIn(delay: 140.ms, duration: 400.ms).slideY(begin: 0.04),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _AttendancePlanCard extends StatelessWidget {
  final bool expanded;
  final VoidCallback onToggle;
  final TextEditingController semesterController;
  final TextEditingController hoursPerWeekController;
  final Map<String, dynamic>? plan;
  final int maxAllowedAbsences;
  final bool saving;
  final VoidCallback onSave;
  final VoidCallback onExtraClass;
  final VoidCallback onCancelledClass;

  const _AttendancePlanCard({
    required this.expanded,
    required this.onToggle,
    required this.semesterController,
    required this.hoursPerWeekController,
    required this.plan,
    required this.maxAllowedAbsences,
    required this.saving,
    required this.onSave,
    required this.onExtraClass,
    required this.onCancelledClass,
  });

  int _intVal(dynamic v) {
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final extra = _intVal(plan?['extraClassesRecorded'] ?? plan?['extra_classes_recorded']);
    final cancelled = _intVal(plan?['cancelledClassesRecorded'] ?? plan?['cancelled_classes_recorded']);
    final planned = _intVal(plan?['plannedSessionCount'] ?? plan?['planned_session_count']);

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('90% Attendance Plan', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text(
                        maxAllowedAbsences > 0
                            ? 'Students may miss up to $maxAllowedAbsences session(s) and stay at or above 90%'
                            : 'Set semester hours to calculate the absence allowance',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Icon(expanded ? Icons.expand_less : Icons.expand_more),
              ],
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 16),
            TextField(
              controller: semesterController,
              keyboardType: TextInputType.number,
              enabled: !saving,
              decoration: const InputDecoration(
                labelText: 'Total hours in semester',
                hintText: 'e.g. 45',
                prefixIcon: Icon(Icons.calendar_month_outlined),
                helperText: 'Planned hours match session length: a double period counts as 2 hours, block as 3',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: hoursPerWeekController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              enabled: !saving,
              decoration: const InputDecoration(
                labelText: 'Hours per week',
                hintText: 'e.g. 3',
                prefixIcon: Icon(Icons.schedule_outlined),
              ),
            ),
            if (planned > 0) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StatusPill(
                    label: '$planned planned sessions',
                    icon: Icons.event_available_outlined,
                    color: const Color(0xFF1E4ED8),
                  ),
                  StatusPill(
                    label: 'Max absences: $maxAllowedAbsences',
                    icon: Icons.warning_amber_outlined,
                    color: const Color(0xFFF59E0B),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            const SectionTitle(title: 'Schedule adjustments (optional)'),
            const SizedBox(height: 6),
            Text(
              'Log extra or cancelled classes for your records. The max absence allowance does not change.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                StatusPill(label: 'Extra: $extra', icon: Icons.add_circle_outline, color: const Color(0xFF10B981)),
                StatusPill(label: 'Cancelled: $cancelled', icon: Icons.remove_circle_outline, color: const Color(0xFFEF4444)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: saving ? null : onExtraClass,
                    icon: const Icon(Icons.add),
                    label: const Text('Extra class'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: saving ? null : onCancelledClass,
                    icon: const Icon(Icons.remove),
                    label: const Text('No class'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            AppButton(
              label: 'Save attendance plan',
              icon: Icons.save_outlined,
              loading: saving,
              onPressed: saving ? null : onSave,
            ),
          ],
        ],
      ),
    );
  }
}

class _AtRiskStudentsCard extends StatelessWidget {
  final String moduleName;
  final List<Map<String, dynamic>> students;
  final bool configured;

  const _AtRiskStudentsCard({
    required this.moduleName,
    required this.students,
    required this.configured,
  });

  double _pct(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  String _name(Map<String, dynamic> s) =>
      (s['studentName'] ?? s['student_name'] ?? s['full_name'] ?? s['name'] ?? 'Student').toString();

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Attendance Alert', style: Theme.of(context).textTheme.titleLarge),
                    Text(moduleName, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              if (students.isNotEmpty)
                StatusPill(
                  label: '${students.length} at risk',
                  icon: Icons.person_outline,
                  color: const Color(0xFFEF4444),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (!configured)
            Text(
              'Save an attendance plan above to track who is close to falling below 90%.',
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else if (students.isEmpty)
            Row(
              children: [
                Icon(Icons.check_circle_outline, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No students are at risk right now.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            )
          else
            ...students.map((s) {
              final pct = _pct(s['currentPct'] ?? s['current_pct']);
              final remaining = s['absencesRemaining'] ?? s['absences_remaining'];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_name(s), style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 4),
                            Text(
                              '${pct.toStringAsFixed(1)}% attendance'
                              '${remaining != null ? ' • $remaining absence(s) left' : ''}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${pct.toStringAsFixed(0)}%',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: const Color(0xFFF59E0B),
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
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

class _SessionColumn {
  final String id;
  final String header;
  final int units;

  const _SessionColumn({required this.id, required this.header, required this.units});
}

class _ModuleReport {
  final List<_SessionColumn> sessions;
  final List<_StudentReportRow> rows;

  const _ModuleReport({required this.sessions, required this.rows});
}

class _StudentReportRow {
  final String id;
  final String name;
  int slNo = 0;
  int totalUnits = 0;
  int presentUnits = 0;
  int absentUnits = 0;
  int medicalUnits = 0;
  int officialUnits = 0;
  final Map<String, String> _statusBySession = {};

  _StudentReportRow({required this.id, required this.name});

  void applySession(String sessionId, String status, int units) {
    if (_statusBySession.containsKey(sessionId)) return;
    _statusBySession[sessionId] = status;
    totalUnits += units;
    switch (status) {
      case 'PRESENT':
      case 'LATE':
        presentUnits += units;
        break;
      case 'MEDICAL_LEAVE':
        medicalUnits += units;
        break;
      case 'OFFICIAL_LEAVE':
        officialUnits += units;
        break;
      default:
        absentUnits += units;
    }
  }

  void ensureSession(String sessionId, int units) {
    if (!_statusBySession.containsKey(sessionId)) {
      applySession(sessionId, 'ABSENT', units);
    }
  }

  String statusFor(String sessionId) => _statusBySession[sessionId] ?? 'ABSENT';

  double get rule1Percentage => totalUnits == 0 ? 0 : ((totalUnits - absentUnits)  / totalUnits) * 100;

  double get rule2Percentage =>
      totalUnits == 0 ? 0 : ((totalUnits - (absentUnits + medicalUnits + officialUnits)) / totalUnits) * 100;
}
