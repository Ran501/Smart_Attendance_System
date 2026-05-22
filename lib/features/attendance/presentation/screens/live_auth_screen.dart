import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../../../services/attendance_service.dart';
import '../../../../services/bluetooth_validation_service.dart';
import '../../../../services/device_service.dart';
import '../../../../services/face_embedding_service.dart';
import '../../../../services/geo_fence_service.dart';
import '../../../../services/liveness_detection_service.dart';
import '../../../../services/wifi_validation_service.dart';
import '../../../../widgets/enterprise_shell.dart';
import '../../../../widgets/natural_camera_preview.dart';

class LiveAuthScreen extends StatefulWidget {
  final Map<String, dynamic> sessionData;

  const LiveAuthScreen({super.key, required this.sessionData});

  @override
  State<LiveAuthScreen> createState() => _LiveAuthScreenState();
}

class _LiveAuthScreenState extends State<LiveAuthScreen> {
  CameraController? _camera;
  Timer? _autoScanTimer;

  final _embedding = FaceEmbeddingService();
  final _liveness = LivenessDetectionService();
  final _geo = GeoFenceService();
  final _device = DeviceService();
  final _wifi = WifiValidationService();
  final _ble = BluetoothValidationService();

  List<LivenessChallenge> _challenges = [];
  int _challengeIndex = 0;
  bool _livenessComplete = false;
  bool _autoScanning = false;
  bool _submitting = false;
  String _instruction = 'Initializing AI camera...';
  double _progress = 0;
  bool _faceVerified = false;
  bool _bleVerified = false;
  bool _wifiVerified = false;
  bool _locationVerified = false;

  @override
  void initState() {
    super.initState();
    _challenges = _liveness.generateChallengeSequence();
    if (_challenges.isNotEmpty) {
      _liveness.startChallenge(_challenges.first);
      _instruction = _instructionForChallenge(_challenges.first);
    }
    _initCamera();
    _embedding.initialize();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _camera = CameraController(
        front,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await _camera!.initialize();
      _startAutoScanLoop();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _instruction = 'Camera unavailable: $e');
    }
  }

  void _startAutoScanLoop() {
    _autoScanTimer?.cancel();
    _autoScanTimer = Timer.periodic(
      const Duration(milliseconds: 900),
      (_) => _autoProcessLivenessStep(),
    );
  }

  Future<void> _autoProcessLivenessStep() async {
    final camera = _camera;
    if (!mounted ||
        camera == null ||
        !camera.value.isInitialized ||
        camera.value.isTakingPicture ||
        _autoScanning ||
        _submitting ||
        _livenessComplete ||
        _challengeIndex >= _challenges.length) {
      return;
    }

    setState(() => _autoScanning = true);

    XFile? file;
    try {
      file = await camera.takePicture();
      final bytes = await File(file.path).readAsBytes();
      final inputImage = InputImage.fromFilePath(file.path);
      final faces = await _embedding.detectFaces(inputImage);

      if (faces.isEmpty) {
        if (mounted) {
          setState(() {
            _progress = 0;
            _faceVerified = false;
            _instruction = 'No face detected. Keep your face inside the circle.';
          });
        }
        return;
      }

      if (faces.length > 1) {
        if (mounted) {
          setState(() {
            _instruction = 'Only one face should be visible during attendance.';
          });
        }
        return;
      }

      final face = faces.first;
      final result = _liveness.processFrame(face);

      if (mounted) {
        setState(() {
          _progress = result.progress.clamp(0.0, 1.0).toDouble();
          _instruction = result.instruction;
          _faceVerified = result.progress > 0.35;
        });
      }

      if (!result.completed) return;

      if (_challengeIndex < _challenges.length - 1) {
        _challengeIndex++;
        _liveness.startChallenge(_challenges[_challengeIndex]);
        if (mounted) {
          setState(() {
            _progress = 0;
            _faceVerified = true;
            _instruction = _instructionForChallenge(_challenges[_challengeIndex]);
          });
        }
        return;
      }

      _autoScanTimer?.cancel();
      if (mounted) {
        setState(() {
          _livenessComplete = true;
          _faceVerified = true;
          _progress = 1;
          _instruction = 'Live face verified. Submitting attendance...';
        });
      }

      await _submitAttendance(bytes, face);
    } catch (e) {
      if (mounted) setState(() => _instruction = 'Camera check failed: $e');
    } finally {
      if (file != null) {
        try {
          await File(file.path).delete();
        } catch (_) {}
      }
      if (mounted) setState(() => _autoScanning = false);
    }
  }

  String _instructionForChallenge(LivenessChallenge challenge) {
    switch (challenge) {
      case LivenessChallenge.smile:
        return 'Smile naturally — it will capture automatically.';
      case LivenessChallenge.turnHeadLeft:
        return 'Turn your head to your left — it will capture automatically.';
      case LivenessChallenge.turnHeadRight:
        return 'Turn your head to your right — it will capture automatically.';
      case LivenessChallenge.blinkTwice:
        return 'Blink twice — it will capture automatically.';
    }
  }

  String _challengeName(LivenessChallenge challenge) {
    switch (challenge) {
      case LivenessChallenge.smile:
        return 'Smile';
      case LivenessChallenge.turnHeadLeft:
        return 'Left turn';
      case LivenessChallenge.turnHeadRight:
        return 'Right turn';
      case LivenessChallenge.blinkTwice:
        return 'Blink';
    }
  }

  bool _boolFromSession(
    Map<String, dynamic> session,
    List<String> keys, {
    bool fallback = false,
  }) {
    for (final key in keys) {
      final value = session[key];
      if (value is bool) return value;
      if (value is String) return value.toLowerCase() == 'true';
    }
    return fallback;
  }

  Future<void> _submitAttendance(List<int> bytes, Face face) async {
    setState(() {
      _submitting = true;
      _instruction = 'Running classroom security checks...';
    });

    try {
      final session = widget.sessionData['session'] as Map<String, dynamic>? ?? {};
      final position = await _geo.getCurrentPosition();
      if (position == null) {
        _showResult(false, 'Could not get your location. Please enable GPS.');
        return;
      }

      final geoOk = _geo.isInsideRadius(
        studentLat: position.latitude,
        studentLon: position.longitude,
        centerLat: (session['latitude'] as num?)?.toDouble() ??
            (session['host_latitude'] as num?)?.toDouble() ??
            0,
        centerLon: (session['longitude'] as num?)?.toDouble() ??
            (session['host_longitude'] as num?)?.toDouble() ??
            0,
        radiusMeters: (session['radius_meters'] as num?)?.toDouble() ?? 100,
      );
      setState(() => _locationVerified = geoOk);
      if (!geoOk) {
        _showResult(false, 'Outside classroom geo-fence');
        return;
      }

      final wifiInfo = await _wifi.getWifiInfo();
      final wifiRequired = _boolFromSession(
        session,
        ['wifi_required', 'wifiRequired', 'wifi_enabled', 'wifiEnabled'],
      );
      final wifiOk = _wifi.validateWifi(
        currentSsid: wifiInfo.ssid,
        currentBssid: wifiInfo.bssid,
        allowedSsid: session['wifi_ssid'] as String? ?? session['wifiSsid'] as String?,
        allowedBssid: session['wifi_bssid'] as String? ?? session['wifiBssid'] as String?,
      );
      setState(() => _wifiVerified = wifiOk || !wifiRequired);
      if (wifiRequired && !wifiOk) {
        _showResult(false, 'Campus WiFi validation failed');
        return;
      }

      final bleRequired = _boolFromSession(
        session,
        ['ble_required', 'bleRequired', 'bluetooth_required', 'bluetoothRequired'],
      );
      final bleResult = await _ble.scanForTeacherBeacon(
        sessionId: widget.sessionData['sessionId']?.toString() ?? '',
        expectedDeviceId: session['ble_device_id'] as String? ?? session['bleDeviceId'] as String?,
        expectedNamePrefix: session['ble_name_prefix'] as String? ?? session['bleNamePrefix'] as String?,
      );
      setState(() => _bleVerified = bleResult.verified || !bleRequired);
      if (bleRequired && !bleResult.verified) {
        _showResult(false, bleResult.message);
        return;
      }

      setState(() => _instruction = 'Generating secure face embedding...');
      final embedding = await _embedding.generateEmbedding(
        Uint8List.fromList(bytes),
        face,
      );
      if (embedding == null) {
        _showResult(
          false,
          'Face embedding model is not available. Check mobile_face_net.tflite asset.',
        );
        return;
      }

      final deviceId = await _device.getDeviceId();
      final fingerprint = await _device.getDeviceFingerprint();

      final result = await AttendanceService().submitAttendance({
        'sessionId': widget.sessionData['sessionId'],
        'sessionToken': widget.sessionData['sessionToken'],
        'liveEmbedding': embedding,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'deviceId': deviceId,
        'deviceFingerprint': fingerprint,
        'livenessPassed': true,
        'livenessScore': 1.0,
        'locationAccuracy': position.accuracy,
        'wifiSsid': wifiInfo.ssid,
        'wifiBssid': wifiInfo.bssid,
        ...bleResult.toJson(),
      });

      _showResult(
        result['accepted'] == true,
        result['message'] as String? ?? result['reason'] as String? ?? 'Done',
        confidence: (result['confidence'] as num?)?.toDouble(),
      );
    } catch (e) {
      _showResult(false, _friendlyError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _friendlyError(Object e) {
    final text = e.toString();
    if (text.startsWith('Exception: ')) return text.substring(11);
    return text;
  }

  void _showResult(bool success, String message, {double? confidence}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        icon: Icon(
          success ? Icons.check_circle : Icons.error,
          color: success ? Colors.green : Colors.red,
          size: 48,
        ),
        title: Text(success ? 'Attendance Marked' : 'Attendance Rejected'),
        content: Text(
          confidence != null
              ? '$message\nFace confidence: ${(confidence * 100).toStringAsFixed(1)}%'
              : message,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (context.mounted) context.go('/student');
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _autoScanTimer?.cancel();
    _camera?.dispose();
    _embedding.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progressValue = _challenges.isEmpty
        ? 0.0
        : ((_challengeIndex + _progress) / _challenges.length)
            .clamp(0.0, 1.0)
            .toDouble();

    return EnterpriseScaffold(
      appBar: AppBar(
        title: const Text('Live AI Verification'),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_camera?.value.isInitialized == true)
                  NaturalCameraPreview(controller: _camera!)
                else
                  const Center(child: CircularProgressIndicator()),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _FaceScannerPainter(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                Positioned(
                  top: 96,
                  left: 16,
                  right: 16,
                  child: GlassCard(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _instruction,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          GlassCard(
            radius: 28,
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: progressValue,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(999),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    _CheckChip(label: 'Face Live', done: _faceVerified),
                    _CheckChip(label: 'Bluetooth', done: _bleVerified),
                    _CheckChip(label: 'WiFi', done: _wifiVerified),
                    _CheckChip(label: 'Location', done: _locationVerified),
                  ],
                ),
                const SizedBox(height: 12),
                if (!_livenessComplete) ...[
                  Text(
                    _challenges.isEmpty
                        ? 'Preparing liveness check'
                        : 'Step ${_challengeIndex + 1}/${_challenges.length}: ${_challengeName(_challenges[_challengeIndex])}',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: _autoScanning
                            ? const CircularProgressIndicator(strokeWidth: 2)
                            : const Icon(Icons.videocam, size: 18),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Auto capture is on — no need to take a selfie.',
                          style: Theme.of(context).textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  const SizedBox(height: 10),
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  const Text('Submitting attendance securely...'),
                ],
                const SizedBox(height: 8),
                Text(
                  'Smile and head turn are captured automatically.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.08),
        ],
      ),
    );
  }
}

class _CheckChip extends StatelessWidget {
  final String label;
  final bool done;

  const _CheckChip({required this.label, required this.done});

  @override
  Widget build(BuildContext context) {
    final color = done
        ? const Color(0xFF10B981)
        : Theme.of(context).colorScheme.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _FaceScannerPainter extends CustomPainter {
  final Color color;
  _FaceScannerPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.48);
    final radius = size.width < 420 ? size.width * 0.34 : 150.0;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(rect, 0.2, 1.1, false, paint);
    canvas.drawArc(rect, 1.7, 1.1, false, paint);
    canvas.drawArc(rect, 3.2, 1.1, false, paint);
    canvas.drawArc(rect, 4.7, 1.1, false, paint);

    final guidePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(center, radius * 0.72, guidePaint);
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      guidePaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      guidePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _FaceScannerPainter oldDelegate) =>
      oldDelegate.color != color;
}
