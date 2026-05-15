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
  final List<({String angleType, List<double> embedding})> _captured = [];
  int _currentAngle = 0;
  bool _processing = false;
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
    _camera = CameraController(front, ResolutionPreset.medium, enableAudio: false);
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

      final embedding = await _embeddingService.generateEmbedding(bytes, faces.first);
      _captured.add((angleType: _angles[_currentAngle], embedding: embedding));

      if (_currentAngle < _angles.length - 1) {
        setState(() {
          _currentAngle++;
          _status = 'Captured! Next: ${_angles[_currentAngle]} angle';
        });
      } else {
        setState(() => _status = 'All angles captured. Tap Submit.');
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
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
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
    return Scaffold(
      appBar: AppBar(title: const Text('Face Registration')),
      body: Column(
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
                            border: Border.all(color: Colors.greenAccent, width: 3),
                            borderRadius: BorderRadius.circular(120),
                          ),
                        ),
                      ),
                    ],
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                LinearProgressIndicator(value: (_currentAngle + 1) / _angles.length),
                const SizedBox(height: 8),
                Text(
                  'Angle ${_currentAngle + 1}/${_angles.length}: ${_angles[_currentAngle]}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (_status != null) Text(_status!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                if (_currentAngle < _angles.length)
                  AppButton(
                    label: 'Capture ${_angles[_currentAngle]}',
                    icon: Icons.camera_alt,
                    loading: _processing,
                    onPressed: _captureAngle,
                  )
                else
                  AppButton(
                    label: 'Submit Registration',
                    icon: Icons.check,
                    loading: _processing,
                    onPressed: _submit,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
