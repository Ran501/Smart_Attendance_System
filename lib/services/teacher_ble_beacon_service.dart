import 'package:flutter/foundation.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/ble/ble_session_beacon.dart';

/// Broadcasts the teacher's session beacon so students can verify proximity.
class TeacherBleBeaconService {
  TeacherBleBeaconService._();
  static final TeacherBleBeaconService instance = TeacherBleBeaconService._();

  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();
  String? _activeSessionId;

  String? get activeSessionId => _activeSessionId;

  Future<bool> start(String sessionId) async {
    if (kIsWeb) return false;
    final id = sessionId.trim();
    if (id.isEmpty) return false;
    _activeSessionId = id;

    final payload = BleSessionBeacon.encodePayload(id);
    final payloadList = payload.toList();

    try {
      final supported = await _peripheral.isSupported;
      if (!supported) {
        debugPrint('[TeacherBLE] Peripheral advertising not supported');
        return false;
      }

      await Permission.bluetoothAdvertise.request();
      await Permission.bluetoothConnect.request();
      await Permission.bluetoothScan.request();

      final perm = await _peripheral.requestPermission();
      if (perm != BluetoothPeripheralState.granted &&
          perm != BluetoothPeripheralState.ready) {
        debugPrint('[TeacherBLE] Advertising permission denied: $perm');
        return false;
      }

      if (await _peripheral.isAdvertising) {
        await _peripheral.stop();
      }

      // localName works on iOS; Android needs manufacturer/service data.
      final state = await _peripheral.start(
        advertiseData: AdvertiseData(
          localName: BleSessionBeacon.displayName(id),
          serviceUuid: BleSessionBeacon.serviceGuid.str128,
          manufacturerId: BleSessionBeacon.manufacturerId,
          manufacturerData: payload,
          serviceDataUuid: BleSessionBeacon.serviceGuid.str128,
          serviceData: payloadList,
          includeDeviceName: false,
        ),
      );

      debugPrint(
        '[TeacherBLE] Advertising session $id (service + manufacturer payload) → $state',
      );

      if (state == BluetoothPeripheralState.granted ||
          state == BluetoothPeripheralState.ready) {
        return await _peripheral.isAdvertising;
      }
      return false;
    } catch (e) {
      debugPrint('[TeacherBLE] Failed to start advertising: $e');
      return false;
    }
  }

  Future<void> stop() async {
    if (kIsWeb) return;
    try {
      if (await _peripheral.isAdvertising) {
        await _peripheral.stop();
      }
    } catch (e) {
      debugPrint('[TeacherBLE] stop error: $e');
    }
    _activeSessionId = null;
  }
}
