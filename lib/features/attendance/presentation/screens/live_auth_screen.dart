import 'dart:async';
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
    if (_challenges.isNotEmpty) {
      _liveness.startChallenge(_challenges.first);
    }
    _instruction = 'Follow the liveness prompts';
    _initCamera();
    _embedding.initialize();
  }

  Future<void> _initCamera() async {
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
    _camera!.startImageStream(_processFrame);
    if (mounted) setState(() {});
  }

  Future<void> _processFrame(CameraImage image) async {
    if (_livenessComplete || _submitting) return;
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
      final file = await _camera!.takePicture();
      final inputImage = InputImage.fromFilePath(file.path);
      final List<Face> faces = await _embedding.detectFaces(inputImage);

      if (faces.isEmpty) {
        setState(() => _instruction = 'No face detected');
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
        } else {
          setState(() => _livenessComplete = true);
          await _submitAttendance(
            await File(file.path).readAsBytes(),
            faces.first,
          );
        }
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
      if (_camera != null &&
          _camera!.value.isInitialized &&
          !_livenessComplete) {
        _camera!.startImageStream(_processFrame);
      }
    }
  }

  Future<void> _submitAttendance(List<int> bytes, Face face) async {
    setState(() {
      _submitting = true;
      _instruction = 'Generating face embedding...';
    });

    try {
      final session =
          widget.sessionData['session'] as Map<String, dynamic>? ?? {};

      // ✅ FIX: null check position before accessing lat/lon/accuracy
      final position = await _geo.getCurrentPosition();
      if (position == null) {
        _showResult(false, 'Could not get your location. Please enable GPS.');
        return;
      }

      final deviceId = await _device.getDeviceId();
      final fingerprint = await _device.getDeviceFingerprint();

      // ✅ FIX: position is now guaranteed non-null here
      final geoOk = _geo.isInsideRadius(
        studentLat: position.latitude,
        studentLon: position.longitude,
        centerLat: (session['latitude'] as num?)?.toDouble() ?? 0,
        centerLon: (session['longitude'] as num?)?.toDouble() ?? 0,
        radiusMeters: (session['radius_meters'] as num?)?.toDouble() ?? 30,
      );

      if (!geoOk) {
        _showResult(false, 'Outside classroom geo-fence');
        return;
      }

      final embedding = await _embedding.generateEmbedding(
        Uint8List.fromList(bytes),
        face,
      );

      final result = await AttendanceService().submitAttendance({
        'sessionId': widget.sessionData['sessionId'],
        'sessionToken': widget.sessionData['sessionToken'],
        'liveEmbedding': embedding,
        'latitude': position.latitude, // ✅ safe — null checked above
        'longitude': position.longitude, // ✅ safe — null checked above
        'deviceId': deviceId,
        'deviceFingerprint': fingerprint,
        'livenessPassed': true,
        'livenessScore': 1.0,
        'locationAccuracy': position.accuracy, // ✅ safe — null checked above
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
              ? '$message\nConfidence: ${(confidence * 100).toStringAsFixed(1)}%'
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
                    'Step ${_challengeIndex + 1}/${_challenges.length}: '
                    '${_challenges[_challengeIndex].name}',
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
