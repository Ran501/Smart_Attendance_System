import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../../../services/device_service.dart';
import '../../../../services/face_embedding_service.dart';
import '../../../../services/face_registration_service.dart';
import '../../../../services/liveness_detection_service.dart';
import '../../../../widgets/app_button.dart';
import '../../../../widgets/natural_camera_preview.dart';

class FaceRegistrationScreen extends StatefulWidget {
  const FaceRegistrationScreen({super.key});

  @override
  State<FaceRegistrationScreen> createState() => _FaceRegistrationScreenState();
}

class _FaceRegistrationScreenState extends State<FaceRegistrationScreen> {
  CameraController? _camera;
  Timer? _autoCaptureTimer;

  final _embeddingService = FaceEmbeddingService();
  final _liveness = LivenessDetectionService();

  final List<({
    String angleType,
    String title,
    String instruction,
    LivenessChallenge challenge,
    IconData icon,
  })> _steps = const [
    (
      angleType: 'front',
      title: 'Smile',
      instruction: 'Smile naturally at the camera',
      challenge: LivenessChallenge.smile,
      icon: Icons.sentiment_satisfied_alt,
    ),
    (
      angleType: 'left',
      title: 'Left turn',
      instruction: 'Turn your head slowly to your left',
      challenge: LivenessChallenge.turnHeadLeft,
      icon: Icons.keyboard_double_arrow_left_rounded,
    ),
    (
      angleType: 'right',
      title: 'Right turn',
      instruction: 'Turn your head slowly to your right',
      challenge: LivenessChallenge.turnHeadRight,
      icon: Icons.keyboard_double_arrow_right_rounded,
    ),
  ];

  final List<({String angleType, List<double> embedding})> _captured = [];

  int _currentStep = 0;
  double _poseProgress = 0;
  bool _detecting = false;
  bool _submitting = false;
  bool _allCaptured = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _initCamera();
    _embeddingService.initialize();
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
      _startCurrentStep();
      _startAutoCaptureLoop();

      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Camera unavailable: $e');
      }
    }
  }

  void _startCurrentStep() {
    if (_currentStep >= _steps.length) return;
    _poseProgress = 0;
    _liveness.startChallenge(_steps[_currentStep].challenge);
    _status = _steps[_currentStep].instruction;
  }

  void _startAutoCaptureLoop() {
    _autoCaptureTimer?.cancel();
    _autoCaptureTimer = Timer.periodic(
      const Duration(milliseconds: 900),
      (_) => _autoCaptureCurrentStep(),
    );
  }

  Future<void> _autoCaptureCurrentStep() async {
    final camera = _camera;
    if (!mounted ||
        camera == null ||
        !camera.value.isInitialized ||
        camera.value.isTakingPicture ||
        _detecting ||
        _submitting ||
        _allCaptured) {
      return;
    }

    setState(() {
      _detecting = true;
      _status = 'Looking for ${_steps[_currentStep].title.toLowerCase()}...';
    });

    XFile? file;
    try {
      file = await camera.takePicture();
      final bytes = await File(file.path).readAsBytes();
      final inputImage = InputImage.fromFilePath(file.path);
      final faces = await _embeddingService.detectFaces(inputImage);

      if (faces.isEmpty) {
        if (mounted) {
          setState(() {
            _poseProgress = 0;
            _status = 'No face detected. Keep your face inside the oval.';
          });
        }
        return;
      }

      if (faces.length > 1) {
        if (mounted) {
          setState(() {
            _status = 'Only one face should be visible.';
          });
        }
        return;
      }

      final face = faces.first;
      final result = _liveness.processFrame(face);

      if (mounted) {
        setState(() {
          _poseProgress = result.progress.clamp(0.0, 1.0).toDouble();
          _status = result.instruction;
        });
      }

      if (!result.completed) return;

      final embedding = await _embeddingService.generateEmbedding(
        Uint8List.fromList(bytes),
        face,
      );

      if (embedding == null) {
        if (mounted) {
          setState(
            () => _status =
                'Face model not loaded. Make sure mobile_face_net.tflite is in assets/models/.',
          );
        }
        return;
      }

      _captured.add((
        angleType: _steps[_currentStep].angleType,
        embedding: embedding,
      ));

      if (_currentStep < _steps.length - 1) {
        if (mounted) {
          setState(() {
            _status = '${_steps[_currentStep].title} captured ✓';
            _currentStep++;
            _startCurrentStep();
          });
        } else {
          _currentStep++;
          _startCurrentStep();
        }
      } else {
        _autoCaptureTimer?.cancel();
        if (mounted) {
          setState(() {
            _allCaptured = true;
            _poseProgress = 1;
            _status = 'All live face poses captured. Submit to finish.';
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Camera check failed: $e');
    } finally {
      if (file != null) {
        try {
          await File(file.path).delete();
        } catch (_) {}
      }
      if (mounted) setState(() => _detecting = false);
    }
  }

  Future<void> _submit() async {
    if (_captured.length < _steps.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete all live face checks')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await DeviceService().verifyDevice();
      await FaceRegistrationService().registerEmbeddings(_captured);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Face registered successfully')),
        );
        context.go('/student');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _autoCaptureTimer?.cancel();
    _camera?.dispose();
    _embeddingService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final overallProgress = _allCaptured
        ? 1.0
        : ((_currentStep + _poseProgress) / _steps.length).clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(title: const Text('Face Registration')),
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        bottom: true,
        child: Column(
          children: [
            Expanded(
              child: _camera?.value.isInitialized == true
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        NaturalCameraPreview(controller: _camera!),
                        Center(
                          child: Container(
                            width: 230,
                            height: 300,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: _allCaptured
                                    ? Colors.greenAccent
                                    : Colors.lightGreenAccent,
                                width: 3,
                              ),
                              borderRadius: BorderRadius.circular(130),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 12,
                          left: 0,
                          right: 0,
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: List.generate(_steps.length, (i) {
                              final done = i < _captured.length;
                              final current = i == _currentStep && !_allCaptured;
                              final step = _steps[i];
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: done
                                      ? Colors.green
                                      : current
                                          ? Colors.orange
                                          : Colors.black54,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      done ? Icons.check_circle : step.icon,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      step.title,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ),
                        ),
                      ],
                    )
                  : const Center(child: CircularProgressIndicator()),
            ),
            Container(
              color: Theme.of(context).scaffoldBackgroundColor,
              padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: overallProgress,
                      minHeight: 6,
                      backgroundColor: Colors.grey.shade300,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _allCaptured ? Colors.green : Colors.blue,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _allCaptured
                        ? 'All ${_steps.length} live checks captured ✓'
                        : 'Auto ${_steps[_currentStep].title} capture',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _status ?? 'Camera is preparing...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: _allCaptured ? Colors.green : Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _allCaptured
                      ? AppButton(
                          label: 'Submit Registration',
                          icon: Icons.check_circle,
                          loading: _submitting,
                          onPressed: _submit,
                        )
                      : AppButton(
                          label: _detecting
                              ? 'Auto checking...'
                              : 'Auto capture enabled',
                          icon: Icons.auto_awesome,
                          loading: _detecting,
                          onPressed: null,
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
