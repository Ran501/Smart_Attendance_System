class AppConstants {
  static const String appName = 'FacePass Bhutan';
  static const String appTagline = 'AI Smart Campus Attendance';

  /// Server uses the same value via FACE_MATCH_THRESHOLD (cosine similarity).
  static const double faceMatchThreshold = 0.75;

  /// Server also requires top-2 enrolled poses to average ≥ threshold × this.
  static const double faceMatchTop2Ratio = 0.96;
  static const int defaultSessionDurationMinutes = 5;

  /// Existing backend radius is still used. BLE adds an extra proximity signal.
  static const double hostSessionBaseRadiusMeters = 100;
  static const double gpsFixedBufferMeters = 12;
  static const double maxAccuracyBufferMeters = 20;

  /// BLE RSSI thresholds. Stronger/less negative values mean closer proximity.
  static const int bleStrongRssi = -65;
  static const int bleMinimumRssi = -78;
  static const int bleScanSeconds = 5;

  /// MobileFaceNet output (runtime-detected; 128 or 192 depending on model file).
  static const int embeddingSize = 192;
  static const String tfliteModelPath = 'assets/models/mobile_face_net.tflite';
  static const int inputSize = 112;
}
