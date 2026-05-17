import 'package:dio/dio.dart';
import '../models/attendance_record_model.dart';
import '../models/attendance_session_model.dart';
import 'api_client.dart';

class AttendanceService {
  final _api = ApiClient.instance;

  Future<AttendanceSessionModel> createSession({
    required String classId,
    required String subjectId,
    required String classroomId,
    required double latitude,
    required double longitude,
    double? accuracy,
    int durationMinutes = 5,
    int? radiusMeters,
  }) async {
    final res = await _api.dio.post('/sessions', data: {
      'classId': classId,
      'subjectId': subjectId,
      'classroomId': classroomId,
      'durationMinutes': durationMinutes,
      'latitude': latitude,
      'longitude': longitude,
      if (accuracy != null) 'accuracy': accuracy,
      if (radiusMeters != null) 'radiusMeters': radiusMeters,
    });
    return AttendanceSessionModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> updateSessionLocation({
    required String sessionId,
    required double latitude,
    required double longitude,
    double? accuracy,
  }) async {
    await _api.dio.patch('/sessions/$sessionId/location', data: {
      'latitude': latitude,
      'longitude': longitude,
      if (accuracy != null) 'accuracy': accuracy,
    });
  }

  Future<({List<Map<String, dynamic>> sessions, List<String> enrolledClassIds})>
      getStudentActiveSessions({
    double? latitude,
    double? longitude,
    double? accuracy,
  }) async {
    try {
      final res = await _api.dio.get(
        '/sessions/student/active',
        queryParameters: {
          if (latitude != null) 'latitude': latitude,
          if (longitude != null) 'longitude': longitude,
          if (accuracy != null) 'accuracy': accuracy,
        },
      );
      final data = res.data;
      if (data is List) {
        return (
          sessions: data.cast<Map<String, dynamic>>(),
          enrolledClassIds: <String>[],
        );
      }
      final map = data as Map<String, dynamic>;
      return (
        sessions: (map['sessions'] as List).cast<Map<String, dynamic>>(),
        enrolledClassIds: List<String>.from(map['enrolledClassIds'] as List? ?? []),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw Exception(
          'Sessions API not found. Stop the old backend and run: cd backend && npm start',
        );
      }
      throw Exception(ApiClient.messageFromDio(e));
    }
  }

  Future<List<AttendanceSessionModel>> getActiveSessions() async {
    final res = await _api.dio.get('/sessions/active');
    return (res.data as List)
        .map((e) => AttendanceSessionModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> validateQr(String sessionId, String sessionToken) async {
    final res = await _api.dio.post('/sessions/validate-qr', data: {
      'sessionId': sessionId,
      'sessionToken': sessionToken,
    });
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> submitAttendance(Map<String, dynamic> payload) async {
    try {
      final res = await _api.dio.post('/attendance/submit', data: payload);
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map) {
        return {
          'accepted': false,
          'reason': data['reason'] ?? data['error'] ?? ApiClient.messageFromDio(e),
        };
      }
      throw Exception(ApiClient.messageFromDio(e));
    }
  }

  Future<List<AttendanceRecordModel>> getHistory() async {
    final res = await _api.dio.get('/attendance/history');
    return (res.data as List)
        .map((e) => AttendanceRecordModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> getStats() async {
    final res = await _api.dio.get('/attendance/stats');
    return res.data as Map<String, dynamic>;
  }

  Future<List<dynamic>> getSessionAttendance(String sessionId) async {
    final res = await _api.dio.get('/sessions/$sessionId/attendance');
    return res.data as List;
  }

  Future<void> closeSession(String sessionId) async {
    await _api.dio.post('/sessions/$sessionId/close');
  }
}
