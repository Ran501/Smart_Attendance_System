import 'package:network_info_plus/network_info_plus.dart';

class WifiValidationService {
  final _networkInfo = NetworkInfo();

  Future<({String? ssid, String? bssid})> getWifiInfo() async {
    try {
      final ssid = await _networkInfo.getWifiName();
      final bssid = await _networkInfo.getWifiBSSID();
      final cleanSsid = ssid?.replaceAll('"', '');
      return (ssid: cleanSsid, bssid: bssid);
    } catch (_) {
      return (ssid: null, bssid: null);
    }
  }

  bool validateWifi({
    required String? currentSsid,
    required String? currentBssid,
    required String? allowedSsid,
    required String? allowedBssid,
  }) {
    if (allowedSsid == null || allowedSsid.isEmpty) return true;
    if (currentSsid == null) return false;
    if (currentSsid == allowedSsid) return true;
    if (allowedBssid != null && currentBssid == allowedBssid) return true;
    return false;
  }
}
