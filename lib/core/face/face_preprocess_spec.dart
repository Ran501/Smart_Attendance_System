/// Shared face pipeline spec — keep in sync with backend/src/utils/facePreprocess.js
class FacePreprocessSpec {
  static const String version = '1.0.0';
  static const int inputSize = 112;
  static const double pixelScale = 127.5;
  static const double normalizeMin = -1.0;
  static const double normalizeMax = 1.0;
  static const String alignment = 'mlkit-eye-landmarks-v1';
  static const String embeddingPostprocess = 'l2-normalize';
  static const String enrollmentStrategy = 'average-5-poses-l2';

  /// Reference eye positions for 112×112 (MobileFaceNet / InsightFace layout).
  static const double refLeftEyeX = 30.2946;
  static const double refLeftEyeY = 51.6963;
  static const double refRightEyeX = 65.5318;
  static const double refRightEyeY = 51.5014;
}
