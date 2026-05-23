import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import '../core/constants/app_constants.dart';
import '../core/face/face_preprocess_spec.dart';

/// Image → aligned 112×112 RGB, ready for MobileFaceNet ([-1, 1] applied later).
class FacePreprocessor {
  static img.Image? prepareAlignedFace(Uint8List imageBytes, Face face) {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) return null;

    final image = img.bakeOrientation(decoded);
    final leftLm = face.landmarks[FaceLandmarkType.leftEye];
    final rightLm = face.landmarks[FaceLandmarkType.rightEye];

    if (leftLm != null && rightLm != null) {
      return _alignWithEyes(
        image,
        leftLm.position.x.toDouble(),
        leftLm.position.y.toDouble(),
        rightLm.position.x.toDouble(),
        rightLm.position.y.toDouble(),
      );
    }

    return _cropFromBoundingBox(image, face.boundingBox);
  }

  static img.Image _alignWithEyes(
    img.Image image,
    double leftX,
    double leftY,
    double rightX,
    double rightY,
  ) {
    final dx = rightX - leftX;
    final dy = rightY - leftY;
    final angleDeg = math.atan2(dy, dx) * 180 / math.pi;

    final cx = image.width / 2;
    final cy = image.height / 2;
    final angleRad = -angleDeg * math.pi / 180;
    var rotated = img.copyRotate(image, angle: -angleDeg);

    final rotLeft = _rotatePoint(leftX, leftY, cx, cy, angleRad);
    final rotRight = _rotatePoint(rightX, rightY, cx, cy, angleRad);
    final rotMidX = (rotLeft.$1 + rotRight.$1) / 2;
    final rotMidY = (rotLeft.$2 + rotRight.$2) / 2;
    final eyeDist = math.sqrt(
      math.pow(rotRight.$1 - rotLeft.$1, 2) + math.pow(rotRight.$2 - rotLeft.$2, 2),
    );

    final refDist = FacePreprocessSpec.refRightEyeX - FacePreprocessSpec.refLeftEyeX;
    final scale = refDist / eyeDist.clamp(1.0, double.infinity);

    final scaledW = (rotated.width * scale).round().clamp(1, 4096);
    final scaledH = (rotated.height * scale).round().clamp(1, 4096);
    rotated = img.copyResize(rotated, width: scaledW, height: scaledH);

    final sMidX = rotMidX * scale;
    final sMidY = rotMidY * scale;
    final cropSize =
        (FacePreprocessSpec.refRightEyeX - FacePreprocessSpec.refLeftEyeX) * 3.2;
    final cropX =
        (sMidX - cropSize / 2).round().clamp(0, rotated.width - 1);
    final cropY =
        (sMidY - cropSize * 0.42).round().clamp(0, rotated.height - 1);
    final cropW = cropSize.round().clamp(1, rotated.width - cropX);
    final cropH = cropSize.round().clamp(1, rotated.height - cropY);

    final cropped =
        img.copyCrop(rotated, x: cropX, y: cropY, width: cropW, height: cropH);
    return img.copyResize(
      cropped,
      width: FacePreprocessSpec.inputSize,
      height: FacePreprocessSpec.inputSize,
    );
  }

  static (double, double) _rotatePoint(
    double x,
    double y,
    double cx,
    double cy,
    double angleRad,
  ) {
    final dx = x - cx;
    final dy = y - cy;
    final cosA = math.cos(angleRad);
    final sinA = math.sin(angleRad);
    return (cx + dx * cosA - dy * sinA, cy + dx * sinA + dy * cosA);
  }

  static img.Image _cropFromBoundingBox(img.Image image, Rect box) {
    final padW = box.width * 0.15;
    final padH = box.height * 0.15;
    final x = (box.left - padW).toInt().clamp(0, image.width - 1);
    final y = (box.top - padH).toInt().clamp(0, image.height - 1);
    final w = (box.width + padW * 2).toInt().clamp(1, image.width - x);
    final h = (box.height + padH * 2).toInt().clamp(1, image.height - y);
    final crop = img.copyCrop(image, x: x, y: y, width: w, height: h);
    return img.copyResize(
      crop,
      width: FacePreprocessSpec.inputSize,
      height: FacePreprocessSpec.inputSize,
    );
  }

  /// MobileFaceNet input: RGB channels scaled to [-1, 1].
  static List<List<List<List<double>>>> toModelInput(img.Image image) {
    final size = FacePreprocessSpec.inputSize;
    return List.generate(
      1,
      (_) => List.generate(
        size,
        (y) => List.generate(size, (x) {
          final pixel = image.getPixel(x, y);
          return [
            (pixel.r.toDouble() / FacePreprocessSpec.pixelScale) +
                FacePreprocessSpec.normalizeMin,
            (pixel.g.toDouble() / FacePreprocessSpec.pixelScale) +
                FacePreprocessSpec.normalizeMin,
            (pixel.b.toDouble() / FacePreprocessSpec.pixelScale) +
                FacePreprocessSpec.normalizeMin,
          ];
        }),
      ),
    );
  }

  static List<double> l2Normalize(List<double> v) {
    final norm = math.sqrt(v.fold(0.0, (s, x) => s + x * x));
    if (norm == 0) return v;
    return v.map((x) => x / norm).toList();
  }

  static List<double> averageEmbeddings(List<List<double>> embeddings) {
    if (embeddings.isEmpty) return [];
    final dim = embeddings.first.length;
    final sum = List<double>.filled(dim, 0);
    for (final emb in embeddings) {
      for (var i = 0; i < dim; i++) {
        sum[i] += emb[i];
      }
    }
    return l2Normalize(sum.map((v) => v / embeddings.length).toList());
  }

  static int expectedEmbeddingDim() => AppConstants.embeddingSize;
}
