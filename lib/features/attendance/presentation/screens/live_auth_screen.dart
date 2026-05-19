import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../../../../core/constants/app_constants.dart';
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
  Timer? _frameTimer;

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
    if (_challenges.isNotEmpty) {
      _liveness.startChallenge(_challenges.first);
    }
    _instruction = 'Follow the liveness prompts';
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
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await _camera!.initialize();
      await _camera!.startImageStream(_processFrame);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Camera initialization error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to initialize camera: $e')),
        );
      }
    }
  }

  Future<void> _processFrame(CameraImage image) async {
    if (_livenessComplete || _submitting) return;

    // Throttle frame processing to every 500ms to avoid performance issues
    if (_frameTimer == null || !_frameTimer!.isActive) {
      _frameTimer = Timer(const Duration(milliseconds: 500), () {});
      // Process frame here when you implement real-time liveness
      // For now, it's just a placeholder
    }
  }

  Future<void> _runLivenessStep() async {
    if (_camera == null || !_camera!.value.isInitialized) {
      _showResult(false, 'Camera not initialized');
      return;
    }

    if (_challengeIndex >= _challenges.length) {
      setState(() => _livenessComplete = true);
      return;
    }

    setState(() => _submitting = true);

    try {
      await _camera!.stopImageStream();
      final XFile file = await _camera!.takePicture();
      final inputImage = InputImage.fromFilePath(file.path);
      final List<Face> faces = await _embedding.detectFaces(inputImage);

      if (faces.isEmpty) {
        setState(() {
          _instruction = 'No face detected - please try again';
          _submitting = false;
        });
        // Restart stream without submitting
        if (_camera != null && _camera!.value.isInitialized) {
          await _camera!.startImageStream(_processFrame);
        }
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
          setState(() => _submitting = false);
          // Restart stream for next challenge
          if (_camera != null && _camera!.value.isInitialized) {
            await _camera!.startImageStream(_processFrame);
          }
        } else {
          setState(() => _livenessComplete = true);
          await _submitAttendance(await file.readAsBytes(), faces.first);
        }
      } else {
        setState(() => _submitting = false);
        // Restart stream for next attempt
        if (_camera != null && _camera!.value.isInitialized) {
          await _camera!.startImageStream(_processFrame);
        }
      }
    } catch (e) {
      debugPrint('Liveness step error: $e');
      setState(() {
        _instruction = 'Error: ${e.toString()}';
        _submitting = false;
      });
      if (_camera != null &&
          _camera!.value.isInitialized &&
          !_livenessComplete) {
        await _camera!.startImageStream(_processFrame);
      }
    }
  }

  Future<void> _submitAttendance(List<int> bytes, Face face) async {
    setState(() {
      _submitting = true;
      _instruction = 'Validating location & device...';
    });

    try {
      final session =
          widget.sessionData['session'] as Map<String, dynamic>? ?? {};

      // Safely extract coordinates
      final centerLat = (session['latitude'] as num?)?.toDouble() ?? 0.0;
      final centerLon = (session['longitude'] as num?)?.toDouble() ?? 0.0;
      final radiusMeters =
          (session['radius_meters'] as num?)?.toDouble() ?? 30.0;

      final position = await _geo.getCurrentPosition();
      final wifi = await _wifi.getWifiInfo();
      final deviceId = await _device.getDeviceId();
      final fingerprint = await _device.getDeviceFingerprint();

      // Check location
      final geoOk = _geo.isInsideRadius(
        studentLat: position.latitude,
        studentLon: position.longitude,
        centerLat: centerLat,
        centerLon: centerLon,
        radiusMeters: radiusMeters,
      );

      if (!geoOk) {
        await _showResult(false, 'Outside classroom geo-fence');
        return;
      }

      // Check WiFi
      final wifiOk = _wifi.validateWifi(
        currentSsid: wifi.ssid,
        currentBssid: wifi.bssid,
        allowedSsid: session['allowed_wifi_ssid'] as String?,
        allowedBssid: session['allowed_wifi_bssid'] as String?,
      );

      if (!wifiOk) {
        await _showResult(false, 'Not connected to campus WiFi');
        return;
      }

      // Generate face embedding
      final embedding = await _embedding.generateEmbedding(
        Uint8List.fromList(bytes),
        face,
      );

      // Submit attendance
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
      });

      await _showResult(
        result['accepted'] == true,
        result['message'] as String? ?? result['reason'] as String? ?? 'Done',
        confidence: (result['confidence'] as num?)?.toDouble(),
      );
    } catch (e) {
      debugPrint('Attendance submission error: $e');
      await _showResult(false, e.toString());
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _showResult(
    bool success,
    String message, {
    double? confidence,
  }) async {
    // Stop camera when showing result
    await _camera?.stopImageStream();

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
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
              if (context.mounted) {
                context.go('/student');
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    _camera?.dispose();
    _embedding.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Verification'),
        automaticallyImplyLeading: false,
      ),
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
                if (!_livenessComplete && _challenges.isNotEmpty) ...[
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
                  const SizedBox(height: 16),
                  AppButton(
                    label: 'Verify Liveness Step',
                    loading: _submitting,
                    onPressed: _runLivenessStep,
                  ),
                ] else if (_livenessComplete)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Submitting attendance...'),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Threshold: ${(AppConstants.faceMatchThreshold * 100).toInt()}% • Geo + WiFi + Device',
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
