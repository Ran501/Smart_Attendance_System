import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../../services/api_client.dart';
import '../../../../widgets/enterprise_shell.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  List<Map<String, dynamic>> _data = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.instance.dio.get('/analytics/teacher');
      if (mounted) {
        setState(() {
          _data = (res.data as List).map((e) => (e as Map).cast<String, dynamic>()).toList();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load analytics: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _sum(String key) => _data.fold<int>(0, (sum, s) => sum + ((s[key] as num?)?.toInt() ?? 0));

  String _sessionId(Map<String, dynamic> s) => (s['id'] ?? s['session_id'] ?? s['sessionId'] ?? '').toString();

  @override
  Widget build(BuildContext context) {
    final totalPresent = _sum('present');
    final totalRejected = _sum('rejected');

    return EnterpriseScaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 94, 16, 32),
          children: [
            GlassCard(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                            Text('Teacher Session Analytics', style: Theme.of(context).textTheme.headlineSmall),
                            const SizedBox(height: 4),
                            Text('Tap any session to view each student and update attendance records.', style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  MetricsQuadGrid(
                    children: [
                      MetricTile(label: 'Sessions', value: '${_data.length}', icon: Icons.event_available_outlined, color: const Color(0xFF1E4ED8)),
                      MetricTile(label: 'Present', value: '$totalPresent', icon: Icons.check_circle_outline, color: const Color(0xFF10B981)),
                      MetricTile(label: 'Rejected', value: '$totalRejected', icon: Icons.gpp_bad_outlined, color: const Color(0xFFEF4444)),
                      MetricTile(label: 'Total', value: '${_data.length}', icon: Icons.list_alt_outlined),
                    ],
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.04),
            const SizedBox(height: 20),
            SectionTitle(
              title: 'Sessions',
              subtitle: 'Open a session to see student names, present, absent, medical leave, and official leave.',
              trailing: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : null,
            ),
            const SizedBox(height: 12),
            if (_data.isEmpty)
              const GlassCard(child: ListTile(leading: Icon(Icons.analytics_outlined), title: Text('No session analytics yet')))
            else
              ..._data.map((s) => _AnalyticsSessionCard(
                    session: s,
                    sessionId: _sessionId(s),
                    onTap: () => context.push('/session/${_sessionId(s)}', extra: s),
                  )),
          ],
        ),
      ),
    );
  }
}

class _AnalyticsSessionCard extends StatelessWidget {
  final Map<String, dynamic> session;
  final String sessionId;
  final VoidCallback onTap;

  const _AnalyticsSessionCard({required this.session, required this.sessionId, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final subject = session['subject_name'] ?? session['subjectName'] ?? session['module_name'] ?? 'Module';
    final className = session['class_id'] ?? session['className'] ?? session['class_name'] ?? 'Class';
    final present = session['present'] ?? session['present_count'] ?? 0;
    final rejected = session['rejected'] ?? session['rejected_count'] ?? 0;
    final total = session['total'] ?? session['student_count'];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        onTap: onTap,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.fact_check_outlined),
            ),
            const SizedBox(width: 14),
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
                      if (total != null) StatusPill(label: 'Total: $total', icon: Icons.groups_outlined, color: const Color(0xFF1E4ED8)),
                    ],
                  ),
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
