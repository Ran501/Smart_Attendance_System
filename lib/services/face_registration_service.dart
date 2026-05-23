import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../core/constants/app_constants.dart';
import 'api_client.dart';
import 'device_service.dart';
import 'face_embedding_service.dart';

class FaceVerifyResult {
  final bool verified;
  final double? similarity;
  final double? minSimilarity;
  final double? maxSimilarity;
  final String? message;

  const FaceVerifyResult({
    required this.verified,
    this.similarity,
    this.minSimilarity,
    this.maxSimilarity,
    this.message,
  });
}

class FaceRegistrationService {
  final _api = ApiClient.instance;
  final _device = DeviceService();
  final _embedding = FaceEmbeddingService();

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

  Future<void> registerEmbeddings(
    List<({String angleType, List<double> embedding})> items,
  ) async {
    if (items.length < 5) {
      throw Exception(
        'Register all 5 poses: smile, up, down, right, and left.',
      );
    }

    for (final item in items) {
      if (item.embedding.isEmpty) {
        throw Exception(
          'Empty embedding for "${item.angleType}". Complete face registration again.',
        );
      }
    }

    final deviceId = await _device.getDeviceId();

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

  Future<bool> isFaceRegistered() async {
    try {
      final res = await _api.dio.get('/face/status');
      final data = res.data;
      if (data is! Map) return false;

      final map = data.cast<String, dynamic>();
      final registered = map['registered'] as bool? ?? false;
      final hasTemplate = map['hasTemplate'] as bool? ?? false;
      final count = map['count'] as int? ?? 0;
      final embeddings = map['embeddings'];
      final embCount = embeddings is List ? embeddings.length : 0;
      final total = count > 0 ? count : embCount;

      debugPrint(
        '[FaceRegistration] status registered=$registered count=$count embCount=$embCount',
      );

      if (hasTemplate) return true;
      if (registered && total >= 5) return true;
      if (total >= 5) return true;
      if (registered && total > 0) return true;
      return false;
    } catch (e) {
      debugPrint('[FaceRegistration] ERROR checking face status: $e');
      return false;
    }
  }

  Future<FaceVerifyResult> verifyEmbeddingDetailed(
    List<double> liveEmbedding, {
    String? sessionId,
  }) async {
    try {
      final response = await _api.dio.post(
        '/face/verify',
        data: {
          'embedding': liveEmbedding,
          if (sessionId != null) 'sessionId': sessionId,
        },
      );
      final data = response.data as Map<String, dynamic>;
      return _parseVerifyResponse(data);
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map) {
        return _parseVerifyResponse(data.cast<String, dynamic>());
      }
      return FaceVerifyResult(
        verified: false,
        message: ApiClient.messageFromDio(e),
      );
    }
  }

  Future<bool> verifyEmbedding(List<double> liveEmbedding) async {
    final result = await verifyEmbeddingDetailed(liveEmbedding);
    return result.verified;
  }

  FaceVerifyResult _parseVerifyResponse(Map<String, dynamic> data) {
    final similarity = (data['similarity'] as num?)?.toDouble() ?? 0;
    final minSimilarity = (data['minSimilarity'] as num?)?.toDouble();
    final maxSimilarity = (data['maxSimilarity'] as num?)?.toDouble();
    final serverVerified = data['verified'] as bool? ?? false;
    final verified = serverVerified;

    return FaceVerifyResult(
      verified: verified,
      similarity: similarity,
      minSimilarity: minSimilarity,
      maxSimilarity: maxSimilarity,
      message: data['message'] as String?,
    );
  }

  void dispose() => _embedding.dispose();
}
