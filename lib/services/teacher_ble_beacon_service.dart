import 'package:flutter/foundation.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:permission_handler/permission_handler.dart';

import 'bluetooth_validation_service.dart';

/// Broadcasts the teacher's session beacon so students can verify ~10 m proximity.
class TeacherBleBeaconService {
  TeacherBleBeaconService._();
  static final TeacherBleBeaconService instance = TeacherBleBeaconService._();

  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();
  String? _activeSessionId;

  String? get activeSessionId => _activeSessionId;

  Future<bool> start(String sessionId) async {
    if (kIsWeb) return false;
    _activeSessionId = sessionId;
    final beaconName = BluetoothValidationService.beaconName(sessionId);

    try {
      final supported = await _peripheral.isSupported;
      if (!supported) {
        debugPrint('[TeacherBLE] Peripheral advertising not supported on this device');
        return false;
      }

      await Permission.bluetoothAdvertise.request();
      await Permission.bluetoothConnect.request();

      final perm = await _peripheral.requestPermission();
      if (perm != BluetoothPeripheralState.granted) {
        debugPrint('[TeacherBLE] Advertising permission denied: $perm');
        return false;
      }

      if (await _peripheral.isAdvertising) {
        await _peripheral.stop();
      }

      final state = await _peripheral.start(
        advertiseData: AdvertiseData(
          localName: beaconName,
        ),
      );
      debugPrint('[TeacherBLE] Advertising as "$beaconName" → $state');
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
