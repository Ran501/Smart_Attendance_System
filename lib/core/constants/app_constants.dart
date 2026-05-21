class AppConstants {
  static const String appName = 'Smart Attendance';

  static const double faceMatchThreshold = 0.85;
  static const int defaultSessionDurationMinutes = 5;

  static const double hostSessionBaseRadiusMeters = 100;
  static const double gpsFixedBufferMeters = 12;
  static const double maxAccuracyBufferMeters = 20;

  static const int embeddingSize = 192;
  static const String tfliteModelPath = 'assets/models/mobile_face_net.tflite';
  static const int inputSize = 112;
}