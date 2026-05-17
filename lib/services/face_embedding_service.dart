import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import '../core/constants/app_constants.dart';

class FaceEmbeddingService {
  Interpreter? _interpreter;
  bool _modelLoaded = false;
  bool _modelLoadAttempted = false; // FIX: don't retry every call

  final _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableLandmarks: true,
      enableTracking: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  Future<void> initialize() async {
    if (_modelLoadAttempted) return; // FIX: only attempt once
    _modelLoadAttempted = true;
    try {
      _interpreter = await Interpreter.fromAsset(
        'assets/models/mobile_face_net.tflite',
        options: InterpreterOptions()..threads = 4,
      );
      _modelLoaded = true;
      debugPrint('[FaceEmbedding] TFLite model loaded successfully');
    } catch (e) {
      _modelLoaded = false;
      // FIX: log the actual error instead of silently swallowing it
      debugPrint('[FaceEmbedding] WARNING: TFLite model failed to load: $e');
      debugPrint(
        '[FaceEmbedding] Fallback is NOT suitable for production — embeddings will not match.',
      );
    }
  }

  bool get isModelLoaded => _modelLoaded;

  Future<List<Face>> detectFaces(InputImage image) async {
    return _faceDetector.processImage(image);
  }

  Future<List<double>?> generateEmbedding(
    Uint8List imageBytes,
    Face face,
  ) async {
    await initialize();

    // FIX: return null if model not loaded so callers can handle it explicitly
    if (_interpreter == null) {
      debugPrint(
        '[FaceEmbedding] ERROR: No TFLite model — cannot generate reliable embedding.',
      );
      return null;
    }

    return _runTfliteEmbedding(imageBytes, face);
  }

  List<double>? _runTfliteEmbedding(Uint8List imageBytes, Face face) {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) {
      debugPrint('[FaceEmbedding] ERROR: Could not decode image');
      return null;
    }

    final box = face.boundingBox;

    // FIX: add padding around face crop (15%) for better recognition
    final padW = box.width * 0.15;
    final padH = box.height * 0.15;
    final x = (box.left - padW).toInt().clamp(0, decoded.width - 1);
    final y = (box.top - padH).toInt().clamp(0, decoded.height - 1);
    final w = (box.width + padW * 2).toInt().clamp(1, decoded.width - x);
    final h = (box.height + padH * 2).toInt().clamp(1, decoded.height - y);

    final crop = img.copyCrop(decoded, x: x, y: y, width: w, height: h);
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

    final embedding = List<double>.from(output[0]);

    // FIX: sanity check — all-zeros means model ran but produced garbage
    final hasNonZero = embedding.any((v) => v != 0.0);
    if (!hasNonZero) {
      debugPrint('[FaceEmbedding] ERROR: Model returned all-zeros embedding');
      return null;
    }

    final normalized = _normalize(embedding);
    debugPrint(
      '[FaceEmbedding] Embedding sample (first 5): ${normalized.sublist(0, 5)}',
    );
    return normalized;
  }

  List<List<List<List<double>>>> _imageToFloat32(img.Image image) {
    // FIX: ensure consistent pixel ordering — x (column) iterates inside y (row)
    return List.generate(
      1,
      (_) => List.generate(
        AppConstants.inputSize,
        (y) => List.generate(AppConstants.inputSize, (x) {
          final pixel = image.getPixel(x, y);
          return [
            // FIX: MobileFaceNet expects [-1, 1] normalization — correct
            (pixel.r.toDouble() / 127.5) - 1.0,
            (pixel.g.toDouble() / 127.5) - 1.0,
            (pixel.b.toDouble() / 127.5) - 1.0,
          ];
        }),
      ),
    );
  }

  List<double> _normalize(List<double> v) {
    final norm = math.sqrt(v.fold(0.0, (s, x) => s + x * x));
    if (norm == 0) return v;
    return v.map((x) => x / norm).toList();
  }

  double cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) {
      debugPrint(
        '[FaceEmbedding] ERROR: Embedding length mismatch — ${a.length} vs ${b.length}',
      );
      return 0;
    }
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
