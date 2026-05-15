import 'package:flutter/material.dart';
import '../../../../services/api_client.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  List<dynamic> _data = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ApiClient.instance.dio.get('/analytics/teacher');
      if (mounted) setState(() => _data = res.data as List);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _data.isEmpty
            ? const Center(child: Text('No session analytics yet'))
            : ListView.builder(
                itemCount: _data.length,
                itemBuilder: (_, i) {
                  final s = _data[i] as Map<String, dynamic>;
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: ListTile(
                      title: Text(s['id'] as String? ?? ''),
                      subtitle: Text('${s['subject_name']} • ${s['class_id']}'),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Present: ${s['present'] ?? 0}'),
                          Text('Rejected: ${s['rejected'] ?? 0}',
                              style: const TextStyle(fontSize: 12, color: Colors.red)),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
