import 'api_client.dart';

class CatalogService {
  final _api = ApiClient.instance;

  Future<List<Map<String, dynamic>>> getClasses() async {
    final res = await _api.dio.get('/classes');
    return (res.data as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getSubjects({String? classId}) async {
    final res = await _api.dio.get('/subjects', queryParameters: {
      if (classId != null) 'classId': classId,
    });
    return (res.data as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getClassrooms({String? classId}) async {
    final res = await _api.dio.get('/classrooms', queryParameters: {
      if (classId != null) 'classId': classId,
    });
    return (res.data as List).cast<Map<String, dynamic>>();
  }
}
