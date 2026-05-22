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
    int sessionUnits = 1,
  }) async {
    final safeUnits = sessionUnits.clamp(1, 3).toInt();
    try {
      final res = await _api.dio.post('/sessions', data: {
        'classId': classId,
        'subjectId': subjectId,
        'moduleId': subjectId,
        'classroomId': classroomId,
        'durationMinutes': durationMinutes,
        'sessionUnits': safeUnits,
        'session_units': safeUnits,
        'periodCount': safeUnits,
        'blockPeriods': safeUnits,
        'latitude': latitude,
        'longitude': longitude,
        if (accuracy != null) 'accuracy': accuracy,
        if (radiusMeters != null) 'radiusMeters': radiusMeters,
      });
      return AttendanceSessionModel.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw Exception(ApiClient.messageFromDio(e));
    }
  }

  Future<bool> updateSessionLocation({
    required String sessionId,
    required double latitude,
    required double longitude,
    double? accuracy,
  }) async {
    try {
      final res = await _api.dio.patch('/sessions/$sessionId/location', data: {
        'latitude': latitude,
        'longitude': longitude,
        if (accuracy != null) 'accuracy': accuracy,
      });

      final data = res.data;
      if (data is Map && data['active'] == false) return false;
      return true;
    } on DioException catch (e) {
      // A 404/410 can happen when the teacher page is still open but the
      // session has already expired or was closed. Do not show this as an app
      // error; the caller will stop the location timer.
      if (e.response?.statusCode == 404 || e.response?.statusCode == 410) {
        return false;
      }
      throw Exception(ApiClient.messageFromDio(e));
    }
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
    try {
      final res = await _api.dio.get('/sessions/active');
      final raw = res.data;
      if (raw is! List) return <AttendanceSessionModel>[];
      final sessions = <AttendanceSessionModel>[];
      for (final item in raw) {
        if (item is! Map) continue;
        try {
          sessions.add(
            AttendanceSessionModel.fromJson(item.cast<String, dynamic>()),
          );
        } catch (_) {
          // Skip malformed rows instead of failing the whole dashboard.
        }
      }
      return sessions;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return <AttendanceSessionModel>[];
      }
      throw Exception(ApiClient.messageFromDio(e));
    }
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


  List<Map<String, dynamic>> _mapList(dynamic data) {
    if (data is List) {
      return data.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }
    if (data is Map) {
      for (final key in const [
        'records',
        'attendance',
        'history',
        'sessions',
        'modules',
        'subjects',
        'classes',
        'data',
      ]) {
        final value = data[key];
        if (value is List) {
          return value.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
        }
        if (value is Map) return _mapList(value);
      }
    }
    return <Map<String, dynamic>>[];
  }

  bool _matchesModule(Map<String, dynamic> row, String moduleId) {
    final normalized = moduleId.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    final keys = [
      row['module_id'],
      row['moduleId'],
      row['subject_id'],
      row['subjectId'],
      row['class_id'],
      row['classId'],
      row['module_code'],
      row['moduleCode'],
      row['code'],
      row['id'],
    ];
    return keys.any((value) => value?.toString().trim().toLowerCase() == normalized);
  }

  Future<List<Map<String, dynamic>>> getStudentModuleRecords({required String moduleId}) async {
    final normalized = moduleId.trim();
    if (normalized.isEmpty) return <Map<String, dynamic>>[];
    final encoded = Uri.encodeComponent(normalized);
    final attempts = <String>[
      '/attendance/module/$encoded',
      '/attendance/history/module/$encoded',
      '/attendance/history?moduleId=$encoded',
      '/attendance/history?subjectId=$encoded',
      '/attendance/history?classId=$encoded',
      '/modules/$encoded/attendance',
      '/subjects/$encoded/attendance',
      '/classes/$encoded/attendance',
    ];

    DioException? lastError;
    for (final path in attempts) {
      try {
        final res = await _api.dio.get(path);
        final records = _mapList(res.data);
        if (records.isNotEmpty) return records;
      } on DioException catch (e) {
        lastError = e;
        if (e.response?.statusCode != 404 && e.response?.statusCode != 405) {
          throw Exception(ApiClient.messageFromDio(e));
        }
      }
    }

    try {
      final res = await _api.dio.get('/attendance/history');
      return _mapList(res.data).where((row) => _matchesModule(row, normalized)).toList();
    } on DioException catch (e) {
      if (lastError != null) return <Map<String, dynamic>>[];
      throw Exception(ApiClient.messageFromDio(e));
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> getStudentModuleSessions({required String moduleId}) async {
    final normalized = moduleId.trim();
    if (normalized.isEmpty) return <Map<String, dynamic>>[];
    final encoded = Uri.encodeComponent(normalized);
    final attempts = <String>[
      '/sessions/student/module/$encoded',
      '/student/modules/$encoded/sessions',
      '/modules/$encoded/sessions',
      '/subjects/$encoded/sessions',
      '/classes/$encoded/sessions',
      '/sessions?moduleId=$encoded',
      '/sessions?subjectId=$encoded',
      '/sessions?classId=$encoded',
    ];

    for (final path in attempts) {
      try {
        final res = await _api.dio.get(path);
        final sessions = _mapList(res.data);
        if (sessions.isNotEmpty) return sessions;
      } on DioException catch (e) {
        if (e.response?.statusCode != 404 && e.response?.statusCode != 405) {
          throw Exception(ApiClient.messageFromDio(e));
        }
      }
    }
    return <Map<String, dynamic>>[];
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


  int sessionUnitsOf(Map<String, dynamic> session) {
    final raw = session['session_units'] ??
        session['sessionUnits'] ??
        session['period_count'] ??
        session['periodCount'] ??
        session['block_periods'] ??
        session['blockPeriods'] ??
        session['units'];
    if (raw is num) return raw.toInt().clamp(1, 3).toInt();
    final parsed = int.tryParse(raw?.toString() ?? '');
    return (parsed ?? 1).clamp(1, 3).toInt();
  }

  Future<List<Map<String, dynamic>>> getModuleSessions({required String moduleId}) async {
    final normalized = moduleId.trim();
    final attempts = <String>[
      '/modules/$normalized/sessions',
      '/subjects/$normalized/sessions',
      '/sessions/module/$normalized',
      '/sessions?moduleId=$normalized',
      '/sessions?subjectId=$normalized',
      '/analytics/teacher?moduleId=$normalized',
      '/analytics/teacher?subjectId=$normalized',
    ];

    DioException? lastError;
    for (final path in attempts) {
      try {
        final res = await _api.dio.get(path);
        final data = res.data;
        if (data is List) {
          return data.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
        }
        if (data is Map && data['sessions'] is List) {
          return (data['sessions'] as List).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
        }
        if (data is Map && data['data'] is List) {
          return (data['data'] as List).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
        }
      } on DioException catch (e) {
        lastError = e;
        if (e.response?.statusCode != 404 && e.response?.statusCode != 405) {
          throw Exception(ApiClient.messageFromDio(e));
        }
      }
    }

    // Last fallback for older backend: pull general analytics and filter in app.
    try {
      final res = await _api.dio.get('/analytics/teacher');
      final data = res.data;
      final rows = data is List
          ? data.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList()
          : <Map<String, dynamic>>[];
      return rows.where((s) {
        final keys = [
          s['module_id'],
          s['moduleId'],
          s['subject_id'],
          s['subjectId'],
          s['class_id'],
          s['classId'],
          s['id'],
        ].map((e) => e?.toString()).whereType<String>().toSet();
        return keys.contains(normalized);
      }).toList();
    } on DioException catch (e) {
      if (lastError != null) return <Map<String, dynamic>>[];
      throw Exception(ApiClient.messageFromDio(e));
    }
  }

  Future<List<dynamic>> getSessionAttendance(String sessionId) async {
    final res = await _api.dio.get('/sessions/$sessionId/attendance');
    return res.data as List;
  }


  Future<List<Map<String, dynamic>>> getSessionRoster(String sessionId) async {
    final attempts = <String>[
      '/sessions/$sessionId/roster',
      '/sessions/$sessionId/attendance?includeAll=true',
      '/sessions/$sessionId/attendance',
    ];

    DioException? lastError;
    for (final path in attempts) {
      try {
        final res = await _api.dio.get(path);
        final data = res.data;
        if (data is List) {
          return data.map((e) => (e as Map).cast<String, dynamic>()).toList();
        }
        if (data is Map && data['students'] is List) {
          return (data['students'] as List)
              .map((e) => (e as Map).cast<String, dynamic>())
              .toList();
        }
        if (data is Map && data['records'] is List) {
          return (data['records'] as List)
              .map((e) => (e as Map).cast<String, dynamic>())
              .toList();
        }
      } on DioException catch (e) {
        lastError = e;
        if (e.response?.statusCode != 404 && e.response?.statusCode != 405) {
          throw Exception(ApiClient.messageFromDio(e));
        }
      }
    }
    if (lastError != null) {
      throw Exception(ApiClient.messageFromDio(lastError));
    }
    return <Map<String, dynamic>>[];
  }

  Future<void> updateAttendanceStatus({
    required String sessionId,
    required String status,
    String? recordId,
    String? studentId,
    String? note,
  }) async {
    final normalized = status.toUpperCase();
    final data = {
      'sessionId': sessionId,
      'session_id': sessionId,
      if (recordId != null) 'recordId': recordId,
      if (recordId != null) 'attendanceId': recordId,
      if (studentId != null) 'studentId': studentId,
      if (studentId != null) 'student_id': studentId,
      'status': normalized,
      'attendanceStatus': normalized,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    };

    final attempts = <({String method, String path})>[
      if (recordId != null) (method: 'patch', path: '/attendance/$recordId/status'),
      if (recordId != null) (method: 'patch', path: '/attendance/$recordId'),
      if (recordId != null) (method: 'patch', path: '/attendance/records/$recordId'),
      if (studentId != null) (method: 'patch', path: '/sessions/$sessionId/attendance/$studentId'),
      (method: 'post', path: '/attendance/update'),
    ];

    DioException? lastError;
    for (final attempt in attempts) {
      try {
        if (attempt.method == 'patch') {
          await _api.dio.patch(attempt.path, data: data);
        } else {
          await _api.dio.post(attempt.path, data: data);
        }
        return;
      } on DioException catch (e) {
        lastError = e;
        if (e.response?.statusCode != 404 && e.response?.statusCode != 405) {
          throw Exception(ApiClient.messageFromDio(e));
        }
      }
    }

    throw Exception(
      'Attendance update API is not available on the backend yet. Add one route that updates the existing attendance record status. Last error: ${lastError == null ? 'not found' : ApiClient.messageFromDio(lastError)}',
    );
  }


  Future<void> closeSession(String sessionId) async {
    await _api.dio.post('/sessions/$sessionId/close');
  }
}
