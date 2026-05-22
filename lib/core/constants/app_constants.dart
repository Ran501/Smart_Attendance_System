class AppConstants {
  static const String appName = 'FacePass Bhutan';
  static const String appTagline = 'AI Smart Campus Attendance';

  /// Server uses the same value via FACE_MATCH_THRESHOLD (cosine similarity).
  static const double faceMatchThreshold = 0.75;

  /// Weakest enrolled pose must reach at least threshold × this (server-side too).
  static const double faceMatchMinPoseRatio = 0.88;
  static const int defaultSessionDurationMinutes = 5;

  /// Existing backend radius is still used. BLE adds an extra proximity signal.
  static const double hostSessionBaseRadiusMeters = 100;
  static const double gpsFixedBufferMeters = 12;
  static const double maxAccuracyBufferMeters = 20;

  /// BLE RSSI thresholds. Stronger/less negative values mean closer proximity.
  static const int bleStrongRssi = -65;
  static const int bleMinimumRssi = -78;
  static const int bleScanSeconds = 5;

  static const int embeddingSize = 192;
  static const String tfliteModelPath = 'assets/models/mobile_face_net.tflite';
  static const int inputSize = 112;
}
