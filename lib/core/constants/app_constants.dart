class AppConstants {
  static const String appName = 'FacePass Bhutan';
  static const String appTagline = 'AI Smart Campus Attendance';
  static const String brandIconAsset = 'assets/icon/icon.png';

  /// Server uses the same value via FACE_MATCH_THRESHOLD (cosine similarity).
  static const double faceMatchThreshold = 0.70;

  /// Server also requires top-2 enrolled poses to average ≥ threshold × this.
  static const double faceMatchTop2Ratio = 0.96;
  static const int defaultSessionDurationMinutes = 5;

  /// Attendance proximity: Bluetooth only (~15 m from teacher phone).
  static const double bleMaxDistanceMeters = 15;

  /// Stronger (less negative) RSSI = closer. ~-76 dBm ≈ 15 m for typical phones.
  static const int bleStrongRssi = -65;
  static const int bleMinimumRssi = -76;
  static const int bleScanSeconds = 8;

  /// MobileFaceNet output (runtime-detected; 128 or 192 depending on model file).
  static const int embeddingSize = 192;
  static const String tfliteModelPath = 'assets/models/mobile_face_net.tflite';
  static const int inputSize = 112;
}
