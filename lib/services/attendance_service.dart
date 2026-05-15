import '../models/attendance_record_model.dart';
import '../models/attendance_session_model.dart';
import 'api_client.dart';

class AttendanceService {
  final _api = ApiClient.instance;

  Future<AttendanceSessionModel> createSession({
    required String classId,
    required String subjectId,
    required String classroomId,
    int durationMinutes = 5,
  }) async {
    final res = await _api.dio.post('/sessions', data: {
      'classId': classId,
      'subjectId': subjectId,
      'classroomId': classroomId,
      'durationMinutes': durationMinutes,
    });
    return AttendanceSessionModel.fromJson(res.data as Map<String, dynamic>);
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
    final res = await _api.dio.post('/attendance/submit', data: payload);
    return res.data as Map<String, dynamic>;
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
