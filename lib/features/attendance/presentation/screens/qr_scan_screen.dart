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
  bool _isLoading = false;
  final _attendance = AttendanceService();
  final MobileScannerController _scannerController = MobileScannerController(
    facing: CameraFacing.back,
    torchEnabled: false,
    autoStart: true,
    formats: [BarcodeFormat.qrCode],
  );

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_scanned || _isLoading) return;

    if (capture.barcodes.isEmpty) return;
    final barcode = capture.barcodes.first;
    if (barcode.rawValue == null) return;

    setState(() {
      _scanned = true;
      _isLoading = true;
    });

    try {
      final rawValue = barcode.rawValue!;
      Map<String, dynamic> data;

      // Try to parse JSON
      try {
        data = jsonDecode(rawValue) as Map<String, dynamic>;
      } catch (e) {
        throw Exception(
          'Invalid QR code format. Please scan a valid attendance QR code.',
        );
      }

      // Validate required fields
      if (!data.containsKey('sessionId') || !data.containsKey('sessionToken')) {
        throw Exception('Invalid QR code: Missing session information');
      }

      final sessionId = data['sessionId'] as String;
      final sessionToken = data['sessionToken'] as String;

      // Show loading dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Validating QR code...'),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      final validation = await _attendance.validateQr(sessionId, sessionToken);

      if (mounted) {
        Navigator.pop(context); // Close loading dialog
      }

      if (validation['valid'] != true) {
        throw Exception(validation['error'] ?? 'Invalid session');
      }

      if (mounted) {
        await _scannerController.stop();
        context
            .push(
              '/live-auth',
              extra: {
                'sessionId': sessionId,
                'sessionToken': sessionToken,
                'session': validation['session'],
              },
            )
            .then((_) {
              // Reset when coming back
              setState(() {
                _scanned = false;
                _isLoading = false;
              });
              _scannerController.start();
            });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'Try Again',
              onPressed: () {
                setState(() {
                  _scanned = false;
                  _isLoading = false;
                });
              },
            ),
          ),
        );
        setState(() {
          _scanned = false;
          _isLoading = false;
        });
      }
    }
  }

  void _toggleTorch() {
    _scannerController.toggleTorch();
  }

  void _switchCamera() {
    _scannerController.switchCamera();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Session QR'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: _toggleTorch,
            tooltip: 'Toggle Torch',
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: _switchCamera,
            tooltip: 'Switch Camera',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade700),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Scan the QR code displayed by your teacher to begin attendance verification.',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                MobileScanner(
                  controller: _scannerController,
                  onDetect: _onDetect,
                  errorBuilder: (context, error, child) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 64,
                            color: Colors.red,
                          ),
                          const SizedBox(height: 16),
                          Text('Camera Error: ${error.errorCode}'),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              _scannerController.start();
                              setState(() {});
                            },
                            child: const Text('Restart Camera'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                // Scanning overlay with cutout
                CustomPaint(
                  painter: ScannerOverlayPainter(),
                  child: Container(color: Colors.transparent),
                ),
                if (_isLoading)
                  Container(
                    color: Colors.black54,
                    child: const Center(
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text('Processing QR Code...'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: Text(
                    'Position the QR code within the frame',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Custom painter for scanner overlay
class ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..style = PaintingStyle.fill;

    final scanAreaSize = size.width * 0.7;
    final left = (size.width - scanAreaSize) / 2;
    final top = (size.height - scanAreaSize) / 2;
    final right = left + scanAreaSize;
    final bottom = top + scanAreaSize;

    // Draw dark overlay outside the scan area
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(Rect.fromLTWH(left, top, scanAreaSize, scanAreaSize))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);

    // Draw scan area border
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawRect(
      Rect.fromLTWH(left, top, scanAreaSize, scanAreaSize),
      borderPaint,
    );

    // Draw corner accents
    final cornerPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    const cornerLength = 20.0;

    // Top-left corner
    canvas.drawLine(
      Offset(left, top + cornerLength),
      Offset(left, top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(left, top),
      Offset(left + cornerLength, top),
      cornerPaint,
    );

    // Top-right corner
    canvas.drawLine(
      Offset(right - cornerLength, top),
      Offset(right, top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(right, top),
      Offset(right, top + cornerLength),
      cornerPaint,
    );

    // Bottom-left corner
    canvas.drawLine(
      Offset(left, bottom - cornerLength),
      Offset(left, bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(left, bottom),
      Offset(left + cornerLength, bottom),
      cornerPaint,
    );

    // Bottom-right corner
    canvas.drawLine(
      Offset(right - cornerLength, bottom),
      Offset(right, bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(right, bottom),
      Offset(right, bottom - cornerLength),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
