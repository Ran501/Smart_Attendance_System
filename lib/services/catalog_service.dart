import 'package:dio/dio.dart';
import 'api_client.dart';

class CatalogService {
  final _api = ApiClient.instance;

  List<Map<String, dynamic>> _mapList(dynamic data) {
    if (data is List) {
      return data.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }
    if (data is Map) {
      for (final key in const ['modules', 'subjects', 'classes', 'data']) {
        final value = data[key];
        if (value is List) {
          return value.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
        }
        if (value is Map) return _mapList(value);
      }
    }
    return <Map<String, dynamic>>[];
  }

  Future<List<Map<String, dynamic>>> getClasses() async {
    final res = await _api.dio.get('/classes');
    return _mapList(res.data);
  }

  Future<List<Map<String, dynamic>>> getSubjects({String? classId}) async {
    final res = await _api.dio.get('/subjects', queryParameters: {
      if (classId != null) 'classId': classId,
    });
    return _mapList(res.data);
  }

  Future<List<Map<String, dynamic>>> getClassrooms({String? classId}) async {
    final res = await _api.dio.get('/classrooms', queryParameters: {
      if (classId != null) 'classId': classId,
    });
    return _mapList(res.data);
  }

  /// Teacher dashboard module list.
  ///
  /// It keeps your existing database/API because it first tries newer module
  /// endpoints, then falls back to the existing subject/class endpoints.
  /// Modules for the signed-in teacher only (server filters by `teacher_id`).
  Future<List<Map<String, dynamic>>> getTeacherModules() async {
    final attempts = <String>[
      '/modules/teacher',
      '/teacher/modules',
      '/modules',
    ];

    DioException? lastError;
    for (final path in attempts) {
      try {
        final res = await _api.dio.get(path);
        return _mapList(res.data);
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



  /// Student dashboard module list.
  ///
  /// Shows only the modules/classes joined by the signed-in student. It tries a
  /// few common route names so the Flutter UI can work with both the newer
  /// module API and the older class-enrolment API.
  Future<List<Map<String, dynamic>>> getStudentModules() async {
    final attempts = <String>[
      '/modules/student',
      '/student/modules',
      '/modules/enrolled',
      '/classes/student',
      '/classes/enrolled',
      '/enrolments/modules',
      '/enrollments/modules',
    ];

    DioException? lastError;
    for (final path in attempts) {
      try {
        final res = await _api.dio.get(path);
        final modules = _mapList(res.data);
        if (modules.isNotEmpty) return modules;
      } on DioException catch (e) {
        lastError = e;
        if (e.response?.statusCode != 404 && e.response?.statusCode != 405) {
          throw Exception(ApiClient.messageFromDio(e));
        }
      }
    }

    // Final fallback for older backends: attendance/stats may already include
    // per-module rows. We intentionally do not fall back to the overall total,
    // because the dashboard must show joined modules, not one overall card.
    try {
      final res = await _api.dio.get('/attendance/stats');
      return _mapList(res.data);
    } on DioException catch (e) {
      if (lastError != null) return <Map<String, dynamic>>[];
      throw Exception(ApiClient.messageFromDio(e));
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  /// Student join feature.
  ///
  /// Keeps the existing backend/database flow by trying the module endpoint first
  /// and falling back to the older class join endpoint used in the original app.
  Future<Map<String, dynamic>> joinModule({
    required String moduleId,
    required String password,
  }) async {
    final payload = {
      'moduleId': moduleId,
      'classId': moduleId,
      'password': password,
      'joinPassword': password,
    };
    try {
      final res = await _api.dio.post('/modules/join', data: payload);
      return (res.data as Map).cast<String, dynamic>();
    } on DioException catch (first) {
      if (first.response?.statusCode == 404) {
        try {
          final res = await _api.dio.post('/classes/join', data: payload);
          return (res.data as Map).cast<String, dynamic>();
        } on DioException catch (second) {
          throw Exception(ApiClient.messageFromDio(second));
        }
      }
      throw Exception(ApiClient.messageFromDio(first));
    }
  }

  /// Teacher module creation feature.
  ///
  /// This does not require a new Flutter-side database model. It sends a flexible
  /// payload that supports both newer `/modules` APIs and the older `/classes`
  /// structure already used by the app. Your backend can store the password in
  /// the existing module/class join-password field.
  Future<Map<String, dynamic>> createModule({
    required String moduleName,
    required String moduleId,
    required String password,
    String? className,
    String? department,
    String? section,
  }) async {
    final normalizedId = moduleId.trim().toUpperCase();
    final payload = {
      'id': normalizedId,
      'moduleId': normalizedId,
      'subjectId': normalizedId,
      'classId': normalizedId,
      'code': normalizedId,
      'name': moduleName.trim(),
      'moduleName': moduleName.trim(),
      'subjectName': moduleName.trim(),
      'password': password.trim(),
      'joinPassword': password.trim(),
      if (className != null && className.trim().isNotEmpty) 'className': className.trim(),
      if (department != null && department.trim().isNotEmpty) 'department': department.trim(),
      if (section != null && section.trim().isNotEmpty) 'section': section.trim(),
    };

    final attempts = <String>[
      '/modules/create',
      '/modules',
      '/classes/create',
      '/classes',
    ];

    DioException? lastError;
    for (final path in attempts) {
      try {
        final res = await _api.dio.post(path, data: payload);
        final data = res.data;
        final created = data is Map ? data.cast<String, dynamic>() : <String, dynamic>{'moduleId': normalizedId};

        // Confirm the module exists on this server (catches wrong/local DB).
        final modules = await getTeacherModules();
        final found = modules.any((m) {
          final id = (m['moduleId'] ?? m['module_id'] ?? m['id'] ?? m['subject_id'] ?? '').toString().toUpperCase();
          return id == normalizedId;
        });
        if (!found) {
          throw Exception(
            'Module was not found after saving. Pull to refresh or sign in again.',
          );
        }

        return created;
      } on DioException catch (e) {
        lastError = e;
        if (e.response?.statusCode != 404 && e.response?.statusCode != 405) {
          throw Exception(ApiClient.messageFromDio(e));
        }
      }
    }

    throw Exception(
      'Module creation API is not available on the backend yet. Add one route that stores moduleId and password in your existing classes/modules table. Last error: ${lastError == null ? 'not found' : ApiClient.messageFromDio(lastError)}',
    );
  }

  String _encodedModulePath(String moduleId) =>
      Uri.encodeComponent(moduleId.trim());

  Map<String, dynamic> _planFromResponse(dynamic data) {
    if (data is! Map) return <String, dynamic>{};
    final map = data.cast<String, dynamic>();
    final plan = map['plan'];
    if (plan is Map) return plan.cast<String, dynamic>();
    return map;
  }

  Future<Map<String, dynamic>> getAttendancePlan(String moduleId) async {
    final path = _encodedModulePath(moduleId);
    final res = await _api.dio.get('/modules/$path/attendance-plan');
    return _planFromResponse(res.data);
  }

  Future<Map<String, dynamic>> updateAttendancePlan({
    required String moduleId,
    required int semesterTotalHours,
    required double hoursPerWeek,
  }) async {
    final path = _encodedModulePath(moduleId);
    final payload = {
      'semesterTotalHours': semesterTotalHours,
      'hoursPerWeek': hoursPerWeek,
    };

    DioException? lastError;
    for (final method in ['PUT', 'POST']) {
      try {
        final res = method == 'PUT'
            ? await _api.dio.put('/modules/$path/attendance-plan', data: payload)
            : await _api.dio.post('/modules/$path/attendance-plan', data: payload);
        return _planFromResponse(res.data);
      } on DioException catch (e) {
        lastError = e;
        final code = e.response?.statusCode;
        if (method == 'PUT' && (code == 404 || code == 405 || code == 502 || code == 503)) {
          continue;
        }
        throw Exception(ApiClient.messageFromDio(e));
      }
    }

    if (lastError != null) {
      throw Exception(ApiClient.messageFromDio(lastError));
    }
    return <String, dynamic>{};
  }

  /// Log one extra class or one cancelled (no-class) session for teacher records.
  Future<Map<String, dynamic>> recordAttendancePlanAdjustment({
    required String moduleId,
    int extraClasses = 0,
    int cancelledClasses = 0,
    String? type,
  }) async {
    final path = _encodedModulePath(moduleId);
    final payload = <String, dynamic>{
      if (type != null && type.trim().isNotEmpty) 'type': type.trim(),
      'extraClasses': extraClasses,
      'cancelledClasses': cancelledClasses,
    };

    try {
      final res = await _api.dio.post(
        '/modules/$path/attendance-plan/adjustments',
        data: payload,
      );
      final plan = _planFromResponse(res.data);
      if (plan.isNotEmpty) return plan;
      return getAttendancePlan(moduleId);
    } on DioException catch (e) {
      throw Exception(ApiClient.messageFromDio(e));
    }
  }

  Future<Map<String, dynamic>> logExtraClass(String moduleId) {
    return recordAttendancePlanAdjustment(moduleId: moduleId, type: 'extra');
  }

  Future<Map<String, dynamic>> logCancelledClass(String moduleId) {
    return recordAttendancePlanAdjustment(moduleId: moduleId, type: 'cancelled');
  }
}
