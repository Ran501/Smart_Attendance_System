import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/ble/ble_session_beacon.dart';

class BeaconStartResult {
  final bool success;
  final String message;
  final bool openSettings;

  const BeaconStartResult({
    required this.success,
    required this.message,
    this.openSettings = false,
  });
}

/// Broadcasts the teacher's session beacon so students can verify proximity.
class TeacherBleBeaconService {
  TeacherBleBeaconService._();
  static final TeacherBleBeaconService instance = TeacherBleBeaconService._();

  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();
  String? _activeSessionId;

  String? get activeSessionId => _activeSessionId;

  Future<BeaconStartResult> start(String sessionId) async {
    if (kIsWeb) {
      return const BeaconStartResult(
        success: false,
        message: 'Bluetooth beacon is not supported in the browser',
      );
    }

    final id = sessionId.trim();
    if (id.isEmpty) {
      return const BeaconStartResult(
        success: false,
        message: 'Invalid session id for Bluetooth beacon',
      );
    }
    _activeSessionId = id;

    try {
      final supported = await _peripheral.isSupported;
      if (!supported) {
        return const BeaconStartResult(
          success: false,
          message:
              'This phone cannot broadcast Bluetooth beacons. Try another Android device.',
        );
      }

      if (Platform.isAndroid) {
        await _peripheral.enableBluetooth(askUser: true);
      }

      final permMsg = await _ensurePermissions();
      if (permMsg != null) {
        return BeaconStartResult(
          success: false,
          message: permMsg,
          openSettings: true,
        );
      }

      final peripheralPerm = await _peripheral.requestPermission();
      if (peripheralPerm == BluetoothPeripheralState.permanentlyDenied) {
        return const BeaconStartResult(
          success: false,
          message:
              'Nearby devices permission is blocked. Open app settings and allow Nearby devices.',
          openSettings: true,
        );
      }
      if (peripheralPerm == BluetoothPeripheralState.turnedOff) {
        return const BeaconStartResult(
          success: false,
          message: 'Turn on Bluetooth, then tap Start beacon again.',
        );
      }

      if (await _peripheral.isAdvertising) {
        await _peripheral.stop();
        await Future.delayed(const Duration(milliseconds: 300));
      }

      // Keep the AD packet small (≤31 bytes). Manufacturer data only on Android.
      final payload = BleSessionBeacon.encodePayload(id);
      final advertiseData = AdvertiseData(
        manufacturerId: BleSessionBeacon.manufacturerId,
        manufacturerData: payload,
        localName: BleSessionBeacon.displayName(id),
        includeDeviceName: false,
      );

      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          await _peripheral.start(advertiseData: advertiseData);
        } on PlatformException catch (e) {
          debugPrint('[TeacherBLE] start attempt ${attempt + 1}: ${e.code} ${e.message}');
          if (e.message?.contains('DATA_TOO_LARGE') == true) {
            return const BeaconStartResult(
              success: false,
              message: 'Beacon data too large for this phone. Contact support.',
            );
          }
        }

        final advertising = await _waitUntilAdvertising();
        if (advertising) {
          debugPrint('[TeacherBLE] Advertising session $id');
          return const BeaconStartResult(
            success: true,
            message: 'Bluetooth beacon is on',
          );
        }
        await Future.delayed(const Duration(milliseconds: 400));
      }

      return const BeaconStartResult(
        success: false,
        message:
            'Could not start Bluetooth beacon. Enable Bluetooth, allow Nearby devices, then tap Start beacon.',
        openSettings: true,
      );
    } catch (e) {
      debugPrint('[TeacherBLE] Failed: $e');
      return BeaconStartResult(
        success: false,
        message: 'Bluetooth beacon error: $e',
        openSettings: true,
      );
    }
  }

  Future<bool> _waitUntilAdvertising() async {
    for (var i = 0; i < 15; i++) {
      if (await _peripheral.isAdvertising) return true;
      await Future.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }

  Future<String?> _ensurePermissions() async {
    final advertise = await Permission.bluetoothAdvertise.request();
    final connect = await Permission.bluetoothConnect.request();
    final scan = await Permission.bluetoothScan.request();

    if (advertise.isPermanentlyDenied ||
        connect.isPermanentlyDenied ||
        scan.isPermanentlyDenied) {
      return 'Bluetooth permissions are blocked. Open app settings and allow Nearby devices.';
    }
    if (!advertise.isGranted || !connect.isGranted) {
      return 'Allow Bluetooth and Nearby devices when prompted, then try again.';
    }

    // Some Android OEMs still require location for BLE radio access.
    if (Platform.isAndroid) {
      await Permission.locationWhenInUse.request();
    }
    return null;
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

  Future<void> openAppSettings() => _peripheral.openAppSettings();
}
