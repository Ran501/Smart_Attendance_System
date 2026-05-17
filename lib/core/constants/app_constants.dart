import '../config/api_config.dart';

class AppConstants {
  static const String appName = 'Smart Attendance';
  static String get apiBaseUrl => ApiConfig.baseUrl;
  static const double faceMatchThreshold = 0.85;
  static const int defaultSessionDurationMinutes = 5;

  /// Nominal "near teacher" radius before GPS accuracy buffers are added.
  static const double hostSessionBaseRadiusMeters = 100;
  static const double gpsFixedBufferMeters = 12;
  static const double maxAccuracyBufferMeters = 20;
  static const int embeddingSize = 128;
  static const String tfliteModelPath = 'assets/models/mobile_face_net.tflite';
  static const int inputSize = 112;
}
