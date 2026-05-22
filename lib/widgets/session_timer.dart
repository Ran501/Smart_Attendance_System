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
  Timer? _timer;
  Duration _remaining = Duration.zero;
  bool _expiredNotified = false;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final rem = widget.endsAt.difference(DateTime.now());
    if (!mounted) return;

    if (rem.isNegative || rem == Duration.zero) {
      _timer?.cancel();
      if (!_expiredNotified) {
        _expiredNotified = true;
        widget.onExpired?.call();
      }
      setState(() => _remaining = Duration.zero);
    } else {
      setState(() => _remaining = rem);
    }
  }

  @override
  void didUpdateWidget(covariant SessionTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.endsAt != widget.endsAt) {
      _expiredNotified = false;
      _timer?.cancel();
      _tick();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
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
        expired ? 'Expired' : '$mins:$secs',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 12,
          color: expired ? Colors.red.shade900 : Colors.green.shade900,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
