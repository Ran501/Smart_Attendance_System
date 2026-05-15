import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../../services/attendance_service.dart';

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  bool _scanned = false;
  final _attendance = AttendanceService();

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_scanned) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue == null) return;

    setState(() => _scanned = true);
    try {
      final data = jsonDecode(barcode!.rawValue!) as Map<String, dynamic>;
      final sessionId = data['sessionId'] as String;
      final sessionToken = data['sessionToken'] as String;

      final validation = await _attendance.validateQr(sessionId, sessionToken);
      if (validation['valid'] != true) {
        throw Exception(validation['error'] ?? 'Invalid session');
      }

      if (mounted) {
        context.push('/live-auth', extra: {
          'sessionId': sessionId,
          'sessionToken': sessionToken,
          'session': validation['session'],
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('QR validation failed: $e'), backgroundColor: Colors.red),
        );
        setState(() => _scanned = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Session QR')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Scan the QR code displayed by your teacher to begin attendance verification.',
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: MobileScanner(
              onDetect: _onDetect,
            ),
          ),
        ],
      ),
    );
  }
}
