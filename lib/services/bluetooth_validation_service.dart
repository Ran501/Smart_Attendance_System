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

  /// Path-loss estimate for UI only (RSSI threshold is the real gate).
  static double estimateDistanceMeters(int rssi) {
    const pathLossExponent = 2.2;
    final ratio =
        (AppConstants.bleRssiAtOneMeter - rssi) / (10 * pathLossExponent);
    return math
        .pow(10, ratio)
        .toDouble()
        .clamp(0.5, AppConstants.bleMaxDistanceMeters + 5);
  }

  static bool rssiWithinRange(int rssi, {int? minimumRssi}) {
    return rssi >= (minimumRssi ?? AppConstants.bleMinimumRssi);
  }

  /// One scan: which active session beacons are within Bluetooth range.
  Future<Set<String>> scanNearbySessionIds({
    required List<String> sessionIds,
    int minimumRssi = AppConstants.bleMinimumRssi,
    Duration timeout =
        const Duration(seconds: AppConstants.bleNearbyScanSeconds),
  }) async {
    final targets = sessionIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    if (targets.isEmpty || kIsWeb) return {};

    final bestRssiBySession = <String, int>{};

    try {
      if (!await _ensurePermissions()) return {};

      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) return {};

      final sub = FlutterBluePlus.scanResults.listen((results) {
        for (final result in results) {
          for (final id in targets) {
            if (!BleSessionBeacon.advertisementMatches(
              result.advertisementData,
              id,
            )) {
              continue;
            }
            final prev = bestRssiBySession[id];
            if (prev == null || result.rssi > prev) {
              bestRssiBySession[id] = result.rssi;
            }
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
    } catch (e) {
      debugPrint('[BLE] nearby scan error: $e');
    }

    return bestRssiBySession.entries
        .where((e) => rssiWithinRange(e.value, minimumRssi: minimumRssi))
        .map((e) => e.key)
        .toSet();
  }

  Future<BleValidationResult> scanForTeacherBeacon({
    required String sessionId,
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
          message:
              'Allow Bluetooth and Nearby devices (and Location if asked) in app settings',
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
      var sawBeacon = false;

      final sub = FlutterBluePlus.scanResults.listen((results) {
        for (final result in results) {
          if (!BleSessionBeacon.advertisementMatches(
            result.advertisementData,
            id,
          )) {
            continue;
          }
          sawBeacon = true;
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
          message: sawBeacon
              ? 'Teacher Bluetooth found but signal too weak. Move closer (within ${AppConstants.bleMaxDistanceMeters.toInt()} m).'
              : 'Teacher beacon "$expectedBeacon" not found. Teacher must keep the session screen open with Beacon ON.',
        );
      }

      final rssi = best!.rssi;
      final deviceName = best!.advertisementData.advName.isNotEmpty
          ? best!.advertisementData.advName
          : best!.device.platformName;
      final verified = rssiWithinRange(rssi, minimumRssi: minimumRssi);
      final estM = estimateDistanceMeters(rssi);

      return BleValidationResult(
        verified: verified,
        bestRssi: rssi,
        deviceId: best!.device.remoteId.str,
        deviceName: deviceName.isNotEmpty ? deviceName : expectedBeacon,
        message: verified
            ? 'Near teacher via Bluetooth (signal ${rssi} dBm, ≈${estM.toStringAsFixed(0)} m)'
            : 'Move closer to your teacher (signal ${rssi} dBm). Stay within ${AppConstants.bleMaxDistanceMeters.toInt()} m.',
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
    await Permission.locationWhenInUse.request();
    return scan.isGranted && connect.isGranted;
  }
}
