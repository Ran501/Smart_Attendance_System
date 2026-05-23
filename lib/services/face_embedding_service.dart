import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../core/constants/app_constants.dart';
import '../core/face/face_preprocess_spec.dart';
import 'face_preprocess.dart';

class FaceEmbeddingService {
  Interpreter? _interpreter;
  bool _modelLoaded = false;
  bool _modelLoadAttempted = false;
  int _outputDim = AppConstants.embeddingSize;

  final _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableLandmarks: true,
      enableTracking: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  Future<void> initialize() async {
    if (_modelLoadAttempted) return;
    _modelLoadAttempted = true;
    try {
      _interpreter = await Interpreter.fromAsset(
        'assets/models/mobile_face_net.tflite',
        options: InterpreterOptions()..threads = 4,
      );
      final shape = _interpreter!.getOutputTensor(0).shape;
      _outputDim = shape.fold<int>(1, (a, b) => a * b);
      _modelLoaded = true;
      debugPrint(
        '[FaceEmbedding] TFLite loaded (spec ${FacePreprocessSpec.version}, '
        'output dim $_outputDim)',
      );
    } catch (e) {
      _modelLoaded = false;
      debugPrint('[FaceEmbedding] WARNING: TFLite model failed to load: $e');
    }
  }

  bool get isModelLoaded => _modelLoaded;
  int get outputDim => _outputDim;

  Future<List<Face>> detectFaces(InputImage image) async {
    return _faceDetector.processImage(image);
  }

  Future<List<double>?> generateEmbedding(
    Uint8List imageBytes,
    Face face,
  ) async {
    await initialize();
    if (_interpreter == null) {
      debugPrint('[FaceEmbedding] ERROR: No TFLite model loaded');
      return null;
    }

    final aligned = FacePreprocessor.prepareAlignedFace(imageBytes, face);
    if (aligned == null) {
      debugPrint('[FaceEmbedding] ERROR: Could not align face');
      return null;
    }

    final input = FacePreprocessor.toModelInput(aligned);
    final output = List.generate(
      1,
      (_) => List<double>.filled(_outputDim, 0.0),
    );

    _interpreter!.run(input, output);

    final embedding = List<double>.from(output[0]);
    if (!embedding.any((v) => v != 0.0)) {
      debugPrint('[FaceEmbedding] ERROR: Model returned all-zeros');
      return null;
    }

    return FacePreprocessor.l2Normalize(embedding);
  }

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
