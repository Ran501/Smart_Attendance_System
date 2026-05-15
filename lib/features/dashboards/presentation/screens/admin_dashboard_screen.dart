import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../services/api_client.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  List<dynamic> _users = [];
  List<dynamic> _fraudLogs = [];
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = ApiClient.instance;
      final users = await api.dio.get('/admin/users');
      final fraud = await api.dio.get('/admin/fraud-logs');
      if (mounted) {
        setState(() {
          _users = users.data as List;
          _fraudLogs = fraud.data as List;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(authStateProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.people), label: 'Users'),
              NavigationDestination(icon: Icon(Icons.security), label: 'Fraud Logs'),
            ],
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _tab == 0 ? _usersList() : _fraudList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _usersList() {
    return ListView.builder(
      itemCount: _users.length,
      itemBuilder: (_, i) {
        final u = _users[i] as Map<String, dynamic>;
        return ListTile(
          leading: CircleAvatar(child: Text('${u['role']}'.substring(0, 1).toUpperCase())),
          title: Text(u['full_name'] as String? ?? ''),
          subtitle: Text('${u['email']} • ${u['role']}'),
          trailing: Icon(
            u['is_active'] == true ? Icons.check_circle : Icons.cancel,
            color: u['is_active'] == true ? Colors.green : Colors.grey,
          ),
        );
      },
    );
  }

  Widget _fraudList() {
    if (_fraudLogs.isEmpty) {
      return const Center(child: Text('No fraud attempts logged'));
    }
    return ListView.builder(
      itemCount: _fraudLogs.length,
      itemBuilder: (_, i) {
        final f = _fraudLogs[i] as Map<String, dynamic>;
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            leading: const Icon(Icons.warning, color: Colors.red),
            title: Text(f['attempt_type'] as String? ?? ''),
            subtitle: Text('${f['full_name'] ?? 'Unknown'} • ${f['created_at']}'),
          ),
        );
      },
    );
  }
}
