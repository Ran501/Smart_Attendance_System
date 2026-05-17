import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../../../../services/attendance_service.dart';
import '../../../../services/device_service.dart';
import '../../../../services/face_embedding_service.dart';
import '../../../../services/geo_fence_service.dart';
import '../../../../services/liveness_detection_service.dart';
import '../../../../services/wifi_validation_service.dart';
import '../../../../widgets/app_button.dart';

class LiveAuthScreen extends StatefulWidget {
  final Map<String, dynamic> sessionData;

  const LiveAuthScreen({super.key, required this.sessionData});

  @override
  State<LiveAuthScreen> createState() => _LiveAuthScreenState();
}

class _LiveAuthScreenState extends State<LiveAuthScreen> {
  CameraController? _camera;
  final _embedding = FaceEmbeddingService();
  final _liveness = LivenessDetectionService();
  final _geo = GeoFenceService();
  final _wifi = WifiValidationService();
  final _device = DeviceService();

  List<LivenessChallenge> _challenges = [];
  int _challengeIndex = 0;
  bool _livenessComplete = false;
  bool _submitting = false;
  String _instruction = 'Initializing...';
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _challenges = _liveness.generateChallengeSequence();
    _liveness.startChallenge(_challenges.first);
    _instruction = 'Step 1: Look at the camera and tap Verify';
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
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await _camera!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        setState(() => _instruction = 'Camera error: $e');
      }
    }
  }

  Future<void> _runLivenessStep() async {
    if (_camera == null || !_camera!.value.isInitialized) return;
    setState(() => _submitting = true);
    try {
      final file = await _camera!.takePicture();
      final inputImage = InputImage.fromFilePath(file.path);
      final faces = await _embedding.detectFaces(inputImage);

      if (faces.isEmpty) {
        setState(() => _instruction = 'No face detected — try again');
        return;
      }

      final result = _liveness.processFrame(faces.first);
      setState(() {
        _progress = result.progress;
        _instruction = result.instruction;
      });

      if (result.completed) {
        if (_challengeIndex < _challenges.length - 1) {
          _challengeIndex++;
          _liveness.startChallenge(_challenges[_challengeIndex]);
          setState(() {
            _progress = 0;
            _instruction = 'Next: ${_challenges[_challengeIndex].name}';
          });
        } else {
          setState(() => _livenessComplete = true);
          await _submitAttendance(await File(file.path).readAsBytes(), faces.first);
        }
      }
    } catch (e) {
      setState(() => _instruction = 'Capture failed: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submitAttendance(List<int> bytes, Face face) async {
    setState(() {
      _submitting = true;
      _instruction = 'Validating location & device...';
    });

    try {
      final session = widget.sessionData['session'] as Map<String, dynamic>? ?? {};
      final position = await _geo.getBestPosition();
      if (position == null) {
        _showResult(false, 'Could not get your location. Enable GPS and try outdoors or near a window.');
        return;
      }

      // Bind this phone to the account if not already registered
      try {
        await _device.verifyDevice();
      } catch (e) {
        _showResult(
          false,
          'Device verification failed. Re-register your face on this phone.\n$e',
        );
        return;
      }

      final wifi = await _wifi.getWifiInfo();
      final deviceId = await _device.getDeviceId();
      final fingerprint = await _device.getDeviceFingerprint();

      final usesHost = session['uses_host_location'] == true ||
          session['host_latitude'] != null;
      final baseRadius =
          (session['radius_meters'] as num?)?.toDouble();
      final centerLat = (session['latitude'] as num?)?.toDouble() ??
          (session['host_latitude'] as num?)?.toDouble();
      final centerLon = (session['longitude'] as num?)?.toDouble() ??
          (session['host_longitude'] as num?)?.toDouble();
      final hostAccuracy = (session['host_accuracy'] as num?)?.toDouble();

      if (centerLat == null || centerLon == null) {
        _showResult(false, 'Session location missing. Ask teacher to restart the session.');
        return;
      }

      final proximity = _geo.checkHostProximity(
        studentLat: position.latitude,
        studentLon: position.longitude,
        hostLat: centerLat,
        hostLon: centerLon,
        baseRadius: baseRadius,
        hostAccuracy: hostAccuracy,
        studentAccuracy: position.accuracy,
      );

      if (!proximity.valid) {
        _showResult(
          false,
          usesHost
              ? 'GPS shows ${proximity.distanceMeters.toStringAsFixed(0)}m from teacher '
                  '(allowed ~${proximity.allowedRadiusMeters.toStringAsFixed(0)}m). '
                  'Stand closer together and try again.'
              : 'Outside classroom geo-fence',
        );
        return;
      }

      if (!usesHost) {
        final wifiOk = _wifi.validateWifi(
          currentSsid: wifi.ssid,
          currentBssid: wifi.bssid,
          allowedSsid: session['allowed_wifi_ssid'] as String?,
          allowedBssid: session['allowed_wifi_bssid'] as String?,
        );

        if (!wifiOk) {
          _showResult(false, 'Not connected to campus WiFi');
          return;
        }
      }

      final embedding = await _embedding.generateEmbedding(
        Uint8List.fromList(bytes),
        face,
      );

      final result = await AttendanceService().submitAttendance({
        'sessionId': widget.sessionData['sessionId'],
        'sessionToken': widget.sessionData['sessionToken'],
        'liveEmbedding': embedding,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'wifiSsid': wifi.ssid,
        'wifiBssid': wifi.bssid,
        'deviceId': deviceId,
        'deviceFingerprint': fingerprint,
        'livenessPassed': true,
        'livenessScore': 1.0,
        'locationAccuracy': position.accuracy,
      });

      final accepted = result['accepted'] == true;
      final message = accepted
          ? (result['message'] as String? ?? 'Attendance recorded')
          : (result['reason'] as String? ??
              result['message'] as String? ??
              'Attendance rejected');

      _showResult(
        accepted,
        message,
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
    if (text.startsWith('Exception: ')) return text.substring('Exception: '.length);
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
              ? '$message\nConfidence: ${(confidence * 100).toStringAsFixed(1)}%'
              : message,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.go('/student');
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _releaseCamera() async {
    final camera = _camera;
    _camera = null;
    if (camera != null) {
      if (camera.value.isStreamingImages) {
        await camera.stopImageStream();
      }
      await camera.dispose();
    }
  }

  @override
  void dispose() {
    _releaseCamera();
    _embedding.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live Verification')),
      body: Column(
        children: [
          Expanded(
            child: _camera?.value.isInitialized == true
                ? CameraPreview(_camera!)
                : const Center(child: CircularProgressIndicator()),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (!_livenessComplete) ...[
                  LinearProgressIndicator(
                    value: (_challengeIndex + _progress) / _challenges.length,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _instruction,
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Step ${_challengeIndex + 1}/${_challenges.length}: ${_challenges[_challengeIndex].name}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Two quick steps: smile, then a slight head turn — tap Verify for each',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  AppButton(
                    label: 'Verify Step',
                    loading: _submitting,
                    onPressed: _runLivenessStep,
                  ),
                ] else
                  const CircularProgressIndicator(),
                const SizedBox(height: 8),
                Text(
                  'Geo (${(widget.sessionData['session'] as Map?)?['radius_meters'] ?? 100}m) • Face • Device',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
