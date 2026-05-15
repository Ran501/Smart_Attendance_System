class AppConstants {
  static const String appName = 'Smart Attendance';
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000/api/v1',
  );
  static const double faceMatchThreshold = 0.85;
  static const int defaultSessionDurationMinutes = 5;
  static const int embeddingSize = 128;
  static const String tfliteModelPath = 'assets/models/mobile_face_net.tflite';
  static const int inputSize = 112;
}
