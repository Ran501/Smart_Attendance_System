import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../widgets/enterprise_shell.dart';

class ModuleDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> module;

  const ModuleDetailsScreen({super.key, required this.module});

  double _numValue(List<String> keys, [double fallback = 0]) {
    for (final key in keys) {
      final raw = module[key];
      if (raw is num) return raw.toDouble();
      final parsed = double.tryParse(raw?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final name = module['name'] ?? module['moduleName'] ?? module['subject_name'] ?? module['subjectName'] ?? 'Module';
    final teacher = module['teacher_name'] ?? module['teacherName'] ?? module['teacher'] ?? 'Teacher';
    final percentage = _numValue(['percentage', 'attendancePercentage', 'attendance_percentage']);

    return DefaultTabController(
      length: 4,
      child: EnterpriseScaffold(
        appBar: AppBar(
          title: const Text(AppConstants.appName),
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Attendance'),
              Tab(text: 'Analytics'),
              Tab(text: 'Sessions'),
            ],
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 138, 16, 32),
          children: [
            GlassCard(
              padding: const EdgeInsets.all(22),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name.toString(), style: Theme.of(context).textTheme.headlineMedium),
                        const SizedBox(height: 6),
                        Text('Lecturer: $teacher', style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: 14),
                        StatusPill(
                          label: percentage >= 90 ? 'Safe' : percentage >= 80 ? 'Watch' : 'Risk',
                          icon: Icons.shield_outlined,
                          color: percentage >= 90 ? const Color(0xFF10B981) : percentage >= 80 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444),
                        ),
                      ],
                    ),
                  ),
                  AttendanceLiquidGauge(percentage: percentage, size: 128),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 420,
              child: TabBarView(
                children: [
                  _OverviewTab(module: module),
                  _AttendanceTab(module: module),
                  const _AnalyticsTab(),
                  const _SessionsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  final Map<String, dynamic> module;
  const _OverviewTab({required this.module});

  @override
  Widget build(BuildContext context) {
    return ResponsiveGrid(
      minItemWidth: 170,
      childAspectRatio: 1.25,
      children: [
        MetricTile(label: 'Classes Attended', value: '${module['attended'] ?? module['present'] ?? 0}', icon: Icons.check_circle_outline, color: const Color(0xFF10B981)),
        MetricTile(label: 'Medical Leave', value: '${module['medical_leave'] ?? module['medicalLeave'] ?? 0}', icon: Icons.medical_services_outlined, color: const Color(0xFF3B82F6)),
        MetricTile(label: 'Official Leave', value: '${module['official_leave'] ?? module['officialLeave'] ?? 0}', icon: Icons.event_available_outlined, color: const Color(0xFF8B5CF6)),
        MetricTile(label: 'Absent', value: '${module['absent'] ?? module['rejected'] ?? 0}', icon: Icons.cancel_outlined, color: const Color(0xFFEF4444)),
      ],
    );
  }
}

class _AttendanceTab extends StatelessWidget {
  final Map<String, dynamic> module;
  const _AttendanceTab({required this.module});

  @override
  Widget build(BuildContext context) {
    return const GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Attendance timeline'),
          SizedBox(height: 8),
          Text('Connect this tab to the existing attendance history endpoint to show per-session records for this module.'),
        ],
      ),
    );
  }
}

class _AnalyticsTab extends StatelessWidget {
  const _AnalyticsTab();

  @override
  Widget build(BuildContext context) {
    return const GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Attendance trend analytics'),
          SizedBox(height: 8),
          Text('Reserved for fl_chart / Syncfusion chart binding using your existing backend analytics response.'),
        ],
      ),
    );
  }
}

class _SessionsTab extends StatelessWidget {
  const _SessionsTab();

  @override
  Widget build(BuildContext context) {
    return const GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Session history'),
          SizedBox(height: 8),
          Text('Shows session-by-session attendance once the backend returns module-specific history.'),
        ],
      ),
    );
  }
}
