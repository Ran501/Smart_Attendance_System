import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import '../core/constants/app_constants.dart';

/// Generates face embeddings via TFLite MobileFaceNet when available,
/// with a deterministic fallback for development without the model file.
class FaceEmbeddingService {
  Interpreter? _interpreter;
  bool _modelLoaded = false;
  final _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableLandmarks: true,
      enableTracking: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  Future<void> initialize() async {
    if (_modelLoaded) return;
    try {
      _interpreter = await Interpreter.fromAsset(
        'assets/models/mobile_face_net.tflite',
        options: InterpreterOptions()..threads = 4,
      );
      _modelLoaded = true;
    } catch (_) {
      _modelLoaded = false;
    }
  }

  Future<List<Face>> detectFaces(InputImage image) async {
    return _faceDetector.processImage(image);
  }

  Future<List<double>> generateEmbedding(
    Uint8List imageBytes,
    Face face,
  ) async {
    await initialize();
    if (_interpreter != null) {
      return _runTfliteEmbedding(imageBytes, face);
    }
    return _fallbackEmbedding(imageBytes, face);
  }

  List<double> _runTfliteEmbedding(Uint8List imageBytes, Face face) {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) return _zeros();

    final box = face.boundingBox;
    final crop = img.copyCrop(
      decoded,
      x: box.left.toInt().clamp(0, decoded.width - 1),
      y: box.top.toInt().clamp(0, decoded.height - 1),
      width: box.width.toInt().clamp(1, decoded.width),
      height: box.height.toInt().clamp(1, decoded.height),
    );
    final resized = img.copyResize(
      crop,
      width: AppConstants.inputSize,
      height: AppConstants.inputSize,
    );
    final input = _imageToFloat32(resized);
    final output = List.generate(
      1,
      (_) => List.filled(AppConstants.embeddingSize, 0.0),
    );
    _interpreter!.run(input, output);
    return _normalize(List<double>.from(output[0]));
  }

  List<List<List<List<double>>>> _imageToFloat32(img.Image image) {
    return List.generate(
      1,
      (_) => List.generate(
        AppConstants.inputSize,
        (y) => List.generate(AppConstants.inputSize, (x) {
          final pixel = image.getPixel(x, y);
          return [
            (pixel.r / 127.5) - 1.0,
            (pixel.g / 127.5) - 1.0,
            (pixel.b / 127.5) - 1.0,
          ];
        }),
      ),
    );
  }

  List<double> _fallbackEmbedding(Uint8List imageBytes, Face face) {
    final box = face.boundingBox;
    final landmarks = face.landmarks;
    final seed = [
      box.left,
      box.top,
      box.width,
      box.height,
      face.headEulerAngleY ?? 0,
      face.headEulerAngleZ ?? 0,
      face.leftEyeOpenProbability ?? 0,
      face.rightEyeOpenProbability ?? 0,
      face.smilingProbability ?? 0,
      landmarks[FaceLandmarkType.noseBase]?.position.x ?? 0,
      landmarks[FaceLandmarkType.noseBase]?.position.y ?? 0,
      imageBytes.length % 1000,
    ];
    final rng = math.Random(seed.fold<int>(0, (a, b) => a + b.toInt()));
    final emb = List.generate(
      AppConstants.embeddingSize,
      (_) => rng.nextDouble() * 2 - 1,
    );
    return _normalize(emb);
  }

  List<double> _normalize(List<double> v) {
    final norm = math.sqrt(v.fold(0.0, (s, x) => s + x * x));
    if (norm == 0) return v;
    return v.map((x) => x / norm).toList();
  }

  List<double> _zeros() => List.filled(AppConstants.embeddingSize, 0);

  double cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0;
    double dot = 0, na = 0, nb = 0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    if (na == 0 || nb == 0) return 0;
    return dot / (math.sqrt(na) * math.sqrt(nb));
  }

  void dispose() {
    _interpreter?.close();
    _faceDetector.close();
  }
}
