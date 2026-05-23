class AppConstants {
  static const String appName = 'FacePass Bhutan';
  static const String appTagline = 'AI Smart Campus Attendance';
  static const String brandIconAsset = 'assets/icon/icon.png';

  /// Server uses the same value via FACE_MATCH_THRESHOLD (cosine similarity).
  static const double faceMatchThreshold = 0.70;

  /// Server also requires top-2 enrolled poses to average ≥ threshold × this.
  static const double faceMatchTop2Ratio = 0.96;
  static const int defaultSessionDurationMinutes = 5;

  /// Attendance proximity: Bluetooth only (max 10 m from teacher phone).
  static const double bleMaxDistanceMeters = 10;

  /// RSSI at ~1 m (reference for distance estimate only).
  static const int bleRssiAtOneMeter = -58;

  /// Accept attendance when beacon matches and RSSI is at or above this (~10–12 m).
  static const int bleMinimumRssi = -88;

  /// Strong signal (typically under ~5 m).
  static const int bleStrongRssi = -75;

  static const int bleScanSeconds = 14;
  static const int bleNearbyScanSeconds = 8;

  /// MobileFaceNet output (runtime-detected; 128 or 192 depending on model file).
  static const int embeddingSize = 192;
  static const String tfliteModelPath = 'assets/models/mobile_face_net.tflite';
  static const int inputSize = 112;
}
