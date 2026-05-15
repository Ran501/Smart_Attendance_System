import 'dart:async';
import 'package:flutter/material.dart';

class SessionTimer extends StatefulWidget {
  final DateTime endsAt;
  final VoidCallback? onExpired;

  const SessionTimer({super.key, required this.endsAt, this.onExpired});

  @override
  State<SessionTimer> createState() => _SessionTimerState();
}

class _SessionTimerState extends State<SessionTimer> {
  late Timer _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final rem = widget.endsAt.difference(DateTime.now());
    if (rem.isNegative) {
      _timer.cancel();
      widget.onExpired?.call();
      setState(() => _remaining = Duration.zero);
    } else {
      setState(() => _remaining = rem);
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mins = _remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = _remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    final expired = _remaining == Duration.zero;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: expired ? Colors.red.shade100 : Colors.green.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        expired ? 'SESSION EXPIRED' : '$mins:$secs remaining',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: expired ? Colors.red.shade900 : Colors.green.shade900,
        ),
      ),
    );
  }
}
