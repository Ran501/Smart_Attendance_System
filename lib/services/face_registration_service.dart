import 'api_client.dart';
import 'device_service.dart';

class FaceRegistrationService {
  final _api = ApiClient.instance;
  final _device = DeviceService();

  Future<void> registerEmbeddings(List<({String angleType, List<double> embedding})> items) async {
    final deviceId = await _device.getDeviceId();
    await _api.dio.post('/face/register', data: {
      'deviceId': deviceId,
      'embeddings': items
          .map((e) => {'angleType': e.angleType, 'embedding': e.embedding})
          .toList(),
    });
  }

  Future<bool> isFaceRegistered() async {
    final res = await _api.dio.get('/face/status');
    return res.data['registered'] as bool? ?? false;
  }
}
