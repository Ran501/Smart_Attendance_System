import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/constants/app_constants.dart';

class BleValidationResult {
  final bool verified;
  final int? bestRssi;
  final String message;
  final String? deviceId;
  final String? deviceName;

  const BleValidationResult({
    required this.verified,
    this.bestRssi,
    required this.message,
    this.deviceId,
    this.deviceName,
  });

  Map<String, dynamic> toJson() => {
        'bleVerified': verified,
        'bleRssi': bestRssi,
        'bleMessage': message,
        if (deviceId != null) 'bleDeviceId': deviceId,
        if (deviceName != null) 'bleDeviceName': deviceName,
      };
}

/// Student-side BLE validation.
///
/// Important: flutter_blue_plus supports scanning. Teacher-side broadcasting
/// needs Android/iOS peripheral advertising through a small native bridge or a
/// dedicated beacon advertiser package. This service keeps the existing backend
/// unchanged by sending BLE evidence in the normal attendance payload.
class BluetoothValidationService {
  Future<BleValidationResult> scanForTeacherBeacon({
    required String sessionId,
    String? expectedDeviceId,
    String? expectedNamePrefix,
    int minimumRssi = AppConstants.bleMinimumRssi,
    Duration timeout = const Duration(seconds: AppConstants.bleScanSeconds),
  }) async {
    if (kIsWeb) {
      return const BleValidationResult(
        verified: true,
        message: 'BLE skipped on web build',
      );
    }

    try {
      final permissionsOk = await _ensurePermissions();
      if (!permissionsOk) {
        return const BleValidationResult(
          verified: false,
          message: 'Bluetooth permissions are required for proximity check',
        );
      }

      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        return const BleValidationResult(
          verified: false,
          message: 'Turn on Bluetooth before marking attendance',
        );
      }

      ScanResult? best;
      final sub = FlutterBluePlus.scanResults.listen((results) {
        for (final result in results) {
          final name = result.advertisementData.advName.isNotEmpty
              ? result.advertisementData.advName
              : result.device.platformName;
          final matchesSession = name.toLowerCase().contains(sessionId.toLowerCase()) ||
              name.toLowerCase().startsWith((expectedNamePrefix ?? 'facepass').toLowerCase());
          final matchesDevice = expectedDeviceId == null ||
              result.device.remoteId.str.toLowerCase() == expectedDeviceId.toLowerCase();
          if ((matchesSession || expectedDeviceId != null) && matchesDevice) {
            if (best == null || result.rssi > best!.rssi) best = result;
          }
        }
      });

      await FlutterBluePlus.startScan(timeout: timeout);
      await Future.delayed(timeout);
      await FlutterBluePlus.stopScan();
      await sub.cancel();

      if (best == null) {
        return const BleValidationResult(
          verified: false,
          message: 'Teacher Bluetooth beacon was not detected nearby',
        );
      }

      final rssi = best!.rssi;
      final deviceName = best!.advertisementData.advName.isNotEmpty
          ? best!.advertisementData.advName
          : best!.device.platformName;
      final verified = rssi >= minimumRssi;
      return BleValidationResult(
        verified: verified,
        bestRssi: rssi,
        deviceId: best!.device.remoteId.str,
        deviceName: deviceName,
        message: verified
            ? 'Bluetooth proximity verified'
            : 'Bluetooth signal is weak ($rssi dBm). Move closer to the classroom beacon',
      );
    } catch (e) {
      return BleValidationResult(
        verified: false,
        message: 'Bluetooth validation failed: $e',
      );
    }
  }

  String teacherBeaconName(String sessionId) => 'FacePass-$sessionId';

  Future<bool> _ensurePermissions() async {
    final scan = await Permission.bluetoothScan.request();
    final connect = await Permission.bluetoothConnect.request();
    final location = await Permission.locationWhenInUse.request();
    return scan.isGranted && connect.isGranted && location.isGranted;
  }
}
