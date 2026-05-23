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

  /// Calibrated Tx power at 1 m (used in log-distance estimate).
  static const int bleRssiAtOneMeter = -59;
  static const double blePathLossExponent = 2.35;

  /// Dashboard: enter "in range" (show session banner).
  static const int bleRssiShowSessionEnter = -90;
  static const int bleRssiShowSessionLeave = -94;

  /// Mark attendance: stricter band (~within 10 m, stronger signal).
  static const int bleRssiMarkEnter = -84;
  static const int bleRssiMarkLeave = -88;

  /// Server minimum RSSI (align with [bleRssiMarkEnter]).
  static const int bleMinimumRssi = bleRssiMarkEnter;

  static const int bleRssiMedianWindow = 9;
  static const int bleScanSeconds = 12;

  /// MobileFaceNet output (runtime-detected; 128 or 192 depending on model file).
  static const int embeddingSize = 192;
  static const String tfliteModelPath = 'assets/models/mobile_face_net.tflite';
  static const int inputSize = 112;
}
