import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';
import 'api_client.dart';

class DeviceService {
  final _api = ApiClient.instance;
  String? _cachedDeviceId;

  Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;
    final info = DeviceInfoPlugin();
    String raw;
    try {
      final android = await info.androidInfo;
      raw = '${android.id}-${android.model}-${android.brand}';
    } catch (_) {
      try {
        final ios = await info.iosInfo;
        raw = '${ios.identifierForVendor}-${ios.model}';
      } catch (_) {
        raw = const Uuid().v4();
      }
    }
    _cachedDeviceId = raw;
    return raw;
  }

  Future<String> getDeviceFingerprint() async {
    final id = await getDeviceId();
    final bytes = utf8.encode(id);
    return sha256.convert(bytes).toString();
  }

  Future<Map<String, dynamic>> verifyDevice() async {
    final deviceId = await getDeviceId();
    final fingerprint = await getDeviceFingerprint();
    final res = await _api.dio.post('/device/verify', data: {
      'deviceId': deviceId,
      'deviceFingerprint': fingerprint,
      'deviceName': 'Mobile Device',
    });
    return res.data as Map<String, dynamic>;
  }
}
