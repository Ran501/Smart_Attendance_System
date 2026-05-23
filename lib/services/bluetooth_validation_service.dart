import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/ble/ble_session_beacon.dart';
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

/// Student-side scan for the teacher's session-specific BLE beacon.
class BluetoothValidationService {
  static String beaconName(String sessionId) =>
      BleSessionBeacon.displayName(sessionId);

  static double estimateDistanceMeters(int rssi) {
    const measuredPower = -55;
    const pathLossExponent = 2.0;
    final ratio = (measuredPower - rssi) / (10 * pathLossExponent);
    return math.pow(10, ratio).toDouble().clamp(0.5, 100.0);
  }

  Future<BleValidationResult> scanForTeacherBeacon({
    required String sessionId,
    String? expectedDeviceId,
    int minimumRssi = AppConstants.bleMinimumRssi,
    Duration timeout = const Duration(seconds: AppConstants.bleScanSeconds),
  }) async {
    if (kIsWeb) {
      return const BleValidationResult(
        verified: false,
        message: 'Bluetooth attendance is not supported in the browser',
      );
    }

    final id = sessionId.trim();
    if (id.isEmpty) {
      return const BleValidationResult(
        verified: false,
        message: 'Invalid session for Bluetooth check',
      );
    }

    try {
      final permissionsOk = await _ensurePermissions();
      if (!permissionsOk) {
        return const BleValidationResult(
          verified: false,
          message: 'Bluetooth and nearby-device permissions are required',
        );
      }

      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        return const BleValidationResult(
          verified: false,
          message: 'Turn on Bluetooth before marking attendance',
        );
      }

      final expectedBeacon = beaconName(id);
      ScanResult? best;
      var sawOurService = false;

      final sub = FlutterBluePlus.scanResults.listen((results) {
        for (final result in results) {
          final ad = result.advertisementData;
          if (!BleSessionBeacon.advertisementMatches(ad, id)) continue;

          sawOurService = true;

          if (expectedDeviceId != null &&
              result.device.remoteId.str.toLowerCase() !=
                  expectedDeviceId.toLowerCase()) {
            continue;
          }

          if (best == null || result.rssi > best!.rssi) {
            best = result;
          }
        }
      });

      await FlutterBluePlus.startScan(
        timeout: timeout,
        androidScanMode: AndroidScanMode.lowLatency,
        continuousUpdates: true,
      );
      await Future.delayed(timeout);

      await FlutterBluePlus.stopScan();
      await sub.cancel();

      if (best == null) {
        return BleValidationResult(
          verified: false,
          message: sawOurService
              ? 'Teacher Bluetooth found but signal too weak. Move within ${AppConstants.bleMaxDistanceMeters.toInt()} m and try again.'
              : 'Teacher beacon "$expectedBeacon" not found. Teacher must open the live session screen, enable Bluetooth, and allow Nearby devices — beacon should show ON.',
        );
      }

      final rssi = best!.rssi;
      final deviceName = best!.advertisementData.advName.isNotEmpty
          ? best!.advertisementData.advName
          : best!.device.platformName;
      final estM = estimateDistanceMeters(rssi);
      final verified = rssi >= minimumRssi;

      return BleValidationResult(
        verified: verified,
        bestRssi: rssi,
        deviceId: best!.device.remoteId.str,
        deviceName: deviceName.isNotEmpty ? deviceName : expectedBeacon,
        message: verified
            ? 'Within ${AppConstants.bleMaxDistanceMeters.toInt()} m of teacher (≈${estM.toStringAsFixed(0)} m)'
            : 'Too far from teacher (≈${estM.toStringAsFixed(0)} m, max ${AppConstants.bleMaxDistanceMeters.toInt()} m). Move closer.',
      );
    } catch (e) {
      return BleValidationResult(
        verified: false,
        message: 'Bluetooth validation failed: $e',
      );
    }
  }

  Future<bool> _ensurePermissions() async {
    final scan = await Permission.bluetoothScan.request();
    final connect = await Permission.bluetoothConnect.request();
    await Permission.bluetoothAdvertise.request();
    final location = await Permission.locationWhenInUse.request();
    return scan.isGranted && connect.isGranted && location.isGranted;
  }
}
