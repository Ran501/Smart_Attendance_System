import 'package:flutter/material.dart';
import 'enterprise_shell.dart';

class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color? color;

  const StatCard({super.key, required this.title, required this.value, required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    return MetricTile(label: title, value: value, icon: icon, color: color);
  }
}
