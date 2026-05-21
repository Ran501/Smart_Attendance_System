import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'api_client.dart';
import 'device_service.dart';
import 'face_embedding_service.dart';

class FaceRegistrationService {
  final _api = ApiClient.instance;
  final _device = DeviceService();
  final _embedding = FaceEmbeddingService();

  /// Generates an embedding for a given image+face pair.
  /// Throws if the TFLite model is not loaded.
  Future<List<double>> generateEmbedding(
    Uint8List imageBytes,
    Face face,
  ) async {
    final result = await _embedding.generateEmbedding(imageBytes, face);
    if (result == null) {
      throw Exception(
        'Face model not loaded. Place mobile_face_net.tflite in assets/models/ '
        'and declare it in pubspec.yaml under flutter > assets.',
      );
    }
    debugPrint(
      '[FaceRegistration] Generated embedding, dims: ${result.length}',
    );
    return result;
  }

  /// Uploads all captured embeddings to the backend.
  /// Throws if any embedding is empty or backend returns an error.
  Future<void> registerEmbeddings(
    List<({String angleType, List<double> embedding})> items,
  ) async {
    if (items.isEmpty) {
      throw Exception('No embeddings to register.');
    }

    // Guard: never send empty embeddings
    for (final item in items) {
      if (item.embedding.isEmpty) {
        throw Exception(
          'Empty embedding for angle "${item.angleType}". '
          'Ensure TFLite model is loaded before registration.',
        );
      }
      debugPrint(
        '[FaceRegistration] ${item.angleType}: ${item.embedding.length} dims, '
        'sample: ${item.embedding.sublist(0, 5)}',
      );
    }

    final deviceId = await _device.getDeviceId();

    debugPrint(
      '[FaceRegistration] Sending ${items.length} embeddings to backend...',
    );

    final response = await _api.dio.post(
      '/face/register',
      data: {
        'deviceId': deviceId,
        'embeddings': items
            .map((e) => {'angleType': e.angleType, 'embedding': e.embedding})
            .toList(),
      },
    );

    debugPrint('[FaceRegistration] Backend response: ${response.data}');
  }

  /// Checks if the current user has registered face embeddings.
  Future<bool> isFaceRegistered() async {
    try {
      final res = await _api.dio.get('/face/status');
      final registered = res.data['registered'] as bool? ?? false;
      debugPrint('[FaceRegistration] isFaceRegistered: $registered');
      return registered;
    } catch (e) {
      debugPrint('[FaceRegistration] ERROR checking face status: $e');
      return false;
    }
  }

  /// Verifies a live embedding against the stored ones on the backend.
  /// Returns true if the face matches.
  Future<bool> verifyEmbedding(List<double> liveEmbedding) async {
    try {
      debugPrint(
        '[FaceRegistration] Verifying embedding, dims: ${liveEmbedding.length}',
      );
      final response = await _api.dio.post(
        '/face/verify',
        data: {'embedding': liveEmbedding},
      );
      final verified = response.data['verified'] as bool? ?? false;
      final similarity = response.data['similarity'];
      debugPrint(
        '[FaceRegistration] Verified: $verified, similarity: $similarity',
      );
      return verified;
    } catch (e) {
      debugPrint('[FaceRegistration] ERROR verifying face: $e');
      return false;
    }
  }

  void dispose() => _embedding.dispose();
}
