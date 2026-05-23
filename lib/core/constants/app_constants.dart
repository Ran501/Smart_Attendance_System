class AppConstants {
  static const String appName = 'FacePass Bhutan';
  static const String appTagline = 'AI Smart Campus Attendance';
  static const String brandIconAsset = 'assets/icon/icon.png';

  /// Server uses the same value via FACE_MATCH_THRESHOLD (cosine similarity).
  static const double faceMatchThreshold = 0.65;

  /// Server also requires top-2 enrolled poses to average ≥ threshold × this.
  static const double faceMatchTop2Ratio = 0.96;
  static const int defaultSessionDurationMinutes = 5;

  /// Attendance proximity: Bluetooth only (max ~20 m from teacher phone).
  static const double bleMaxDistanceMeters = 20;

  /// Calibrated Tx power at 1 m (log-distance estimate for UI).
  static const int bleRssiAtOneMeter = -55;
  static const double blePathLossExponent = 2.15;

  /// Enter range (show session / enable mark).
  static const int bleRssiShowSessionEnter = -97;
  static const int bleRssiMarkEnter = -95;

  /// Leave range — much lower than enter so moving the phone does not flicker UI.
  static const int bleRssiShowSessionLeave = -108;
  static const int bleRssiMarkLeave = -106;

  /// Server minimum RSSI (align with [bleRssiMarkEnter]).
  static const int bleMinimumRssi = bleRssiMarkEnter;

  /// After a good reading, keep session visible this long (even if RSSI dips while moving).
  static const int bleSessionHoldSeconds = 30;

  /// Keep "Mark attendance" enabled for this long after a strong reading.
  static const int bleMarkHoldSeconds = 30;

  /// Rolling RSSI window (small = responsive; hold logic prevents flicker).
  static const int bleRssiMedianWindow = 7;
  static const int bleScanSeconds = 10;

  /// MobileFaceNet output (runtime-detected; 128 or 192 depending on model file).
  static const int embeddingSize = 192;
  static const String tfliteModelPath = 'assets/models/mobile_face_net.tflite';
  static const int inputSize = 112;
}
