import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../../../../services/device_service.dart';
import '../../../../services/face_embedding_service.dart';
import '../../../../services/face_registration_service.dart';
import '../../../../widgets/app_button.dart';

class FaceRegistrationScreen extends StatefulWidget {
  const FaceRegistrationScreen({super.key});

  @override
  State<FaceRegistrationScreen> createState() => _FaceRegistrationScreenState();
}

class _FaceRegistrationScreenState extends State<FaceRegistrationScreen> {
  CameraController? _camera;
  final _embeddingService = FaceEmbeddingService();
  final _angles = ['front', 'left', 'right', 'up', 'down'];

  // FIX: List<double> non-nullable — we only add after null-check below
  final List<({String angleType, List<double> embedding})> _captured = [];

  int _currentAngle = 0;
  bool _processing = false;
  bool _allCaptured = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _initCamera();
    _embeddingService.initialize();
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
    if (mounted) setState(() {});
  }

  Future<void> _captureAngle() async {
    if (_camera == null || !_camera!.value.isInitialized || _processing) return;
    setState(() {
      _processing = true;
      _status = 'Detecting face...';
    });

    try {
      final file = await _camera!.takePicture();
      final bytes = await File(file.path).readAsBytes();
      final inputImage = InputImage.fromFilePath(file.path);
      final faces = await _embeddingService.detectFaces(inputImage);

      if (faces.isEmpty) {
        setState(() => _status = 'No face detected. Try again.');
        return;
      }

      // FIX: generateEmbedding returns List<double>? — handle null explicitly
      final embedding = await _embeddingService.generateEmbedding(
        bytes,
        faces.first,
      );

      if (embedding == null) {
        setState(
          () => _status =
              'Face model not loaded. Make sure mobile_face_net.tflite is in assets/models/.',
        );
        return;
      }

      // Only add to _captured after confirming embedding is non-null
      _captured.add((angleType: _angles[_currentAngle], embedding: embedding));

      if (_currentAngle < _angles.length - 1) {
        setState(() {
          _currentAngle++;
          _status = 'Captured! Next: ${_angles[_currentAngle]} angle';
        });
      } else {
        setState(() {
          _allCaptured = true;
          _status = 'All angles captured! Tap Submit to register.';
        });
      }
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      setState(() => _processing = false);
    }
  }

  Future<void> _submit() async {
    if (_captured.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Capture at least 3 angles')),
      );
      return;
    }
    setState(() => _processing = true);
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  void dispose() {
    _camera?.dispose();
    _embeddingService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

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
                        CameraPreview(_camera!),
                        Center(
                          child: Container(
                            width: 220,
                            height: 280,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Colors.greenAccent,
                                width: 3,
                              ),
                              borderRadius: BorderRadius.circular(120),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 12,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(_angles.length, (i) {
                              final done =
                                  i < _currentAngle ||
                                  (i == _currentAngle && _allCaptured);
                              final current =
                                  i == _currentAngle && !_allCaptured;
                              return Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: done
                                      ? Colors.green
                                      : current
                                      ? Colors.orange
                                      : Colors.black45,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _angles[i],
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                      ],
                    )
                  : const Center(child: CircularProgressIndicator()),
            ),

            // ✅ FIX: bottom panel with explicit padding to clear nav bar
            Container(
              color: Theme.of(context).scaffoldBackgroundColor,
              padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
              child: Column(
                mainAxisSize:
                    MainAxisSize.min, // ✅ FIX: don't take more than needed
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _allCaptured
                          ? 1.0
                          : (_currentAngle + 1) / _angles.length,
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
                        ? 'All ${_angles.length} angles captured ✓'
                        : 'Angle ${_currentAngle + 1}/${_angles.length}: ${_angles[_currentAngle].toUpperCase()}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_status != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _status!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: _allCaptured ? Colors.green : Colors.grey[600],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _allCaptured
                      ? AppButton(
                          label: 'Submit Registration',
                          icon: Icons.check_circle,
                          loading: _processing,
                          onPressed: _submit,
                        )
                      : AppButton(
                          label:
                              'Capture ${_angles[_currentAngle].toUpperCase()}',
                          icon: Icons.camera_alt,
                          loading: _processing,
                          onPressed: _captureAngle,
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
