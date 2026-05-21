import 'package:dio/dio.dart';
import 'api_client.dart';

class CatalogService {
  final _api = ApiClient.instance;

  List<Map<String, dynamic>> _mapList(dynamic data) {
    if (data is List) {
      return data.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }
    if (data is Map && data['modules'] is List) {
      return (data['modules'] as List).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }
    if (data is Map && data['subjects'] is List) {
      return (data['subjects'] as List).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }
    if (data is Map && data['classes'] is List) {
      return (data['classes'] as List).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
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
  Future<List<Map<String, dynamic>>> getTeacherModules() async {
    final attempts = <String>[
      '/modules/teacher',
      '/teacher/modules',
      '/modules',
      '/subjects',
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

    // Final fallback: show classes as modules if the existing backend only has
    // classes. This lets the UI work before the backend module route is added.
    try {
      return await getClasses();
    } on DioException catch (e) {
      throw Exception(ApiClient.messageFromDio(e));
    } catch (_) {
      if (lastError != null) throw Exception(ApiClient.messageFromDio(lastError));
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
        if (data is Map) return data.cast<String, dynamic>();
        return {'success': true, 'moduleId': normalizedId};
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
}
