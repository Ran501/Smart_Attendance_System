import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/ble/ble_distance.dart';
import '../core/ble/ble_proximity_state.dart';
import '../core/ble/ble_rssi_smoother.dart';
import '../core/ble/ble_session_beacon.dart';
import '../core/constants/app_constants.dart';

class BleValidationResult {
  final bool verified;
  final int? bestRssi;
  final int? smoothedRssi;
  final double? estimatedMeters;
  final BleProximityBand band;
  final String message;
  final String? deviceId;
  final String? deviceName;

  const BleValidationResult({
    required this.verified,
    this.bestRssi,
    this.smoothedRssi,
    this.estimatedMeters,
    this.band = BleProximityBand.outOfRange,
    required this.message,
    this.deviceId,
    this.deviceName,
  });

  Map<String, dynamic> toJson() => {
        'bleVerified': verified,
        'bleRssi': smoothedRssi ?? bestRssi,
        'bleMessage': message,
        if (deviceId != null) 'bleDeviceId': deviceId,
        if (deviceName != null) 'bleDeviceName': deviceName,
      };
}

/// Student-side scan for the teacher's session-specific BLE beacon.
class BluetoothValidationService {
  static String beaconName(String sessionId) =>
      BleSessionBeacon.displayName(sessionId);

  static double estimateDistanceMeters(int rssi) => estimateBleDistanceMeters(rssi);

  Future<bool> ensurePermissions() => _ensurePermissions();

  /// Mark-attendance scan: collect samples, median RSSI, mark hysteresis.
  Future<BleValidationResult> scanForTeacherBeacon({
    required String sessionId,
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
      if (!await _ensurePermissions()) {
        return const BleValidationResult(
          verified: false,
          message:
              'Allow Bluetooth and Nearby devices (and Location if asked) in app settings',
        );
      }

      if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
        return const BleValidationResult(
          verified: false,
          message: 'Turn on Bluetooth before marking attendance',
        );
      }

      final expectedBeacon = beaconName(id);
      final smoother = BleRssiSmoother(windowSize: AppConstants.bleRssiMedianWindow);
      ScanResult? bestRaw;
      var sawBeacon = false;
      var wasReady = false;

      final sub = FlutterBluePlus.scanResults.listen((results) {
        for (final result in results) {
          if (!BleSessionBeacon.advertisementMatches(
            result.advertisementData,
            id,
          )) {
            continue;
          }
          sawBeacon = true;
          smoother.add(result.rssi);
          if (bestRaw == null || result.rssi > bestRaw!.rssi) {
            bestRaw = result;
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

      final median = smoother.median;
      if (median == null || bestRaw == null) {
        return BleValidationResult(
          verified: false,
          message: sawBeacon
              ? 'Bluetooth signal too weak. Move within ${AppConstants.bleMaxDistanceMeters.toInt()} m of your teacher.'
              : 'Teacher beacon "$expectedBeacon" not found. Teacher must keep the session screen open with Beacon ON.',
        );
      }

      final proximity = BleSessionProximity.fromRssi(
        sessionId: id,
        smoothedRssi: median,
        wasShowing: true,
        wasReady: wasReady,
      );

      final deviceName = bestRaw!.advertisementData.advName.isNotEmpty
          ? bestRaw!.advertisementData.advName
          : bestRaw!.device.platformName;

      return BleValidationResult(
        verified: proximity.readyToMark,
        bestRssi: bestRaw!.rssi,
        smoothedRssi: median,
        estimatedMeters: proximity.estimatedMeters,
        band: proximity.band,
        deviceId: bestRaw!.device.remoteId.str,
        deviceName: deviceName.isNotEmpty ? deviceName : expectedBeacon,
        message: proximity.readyToMark
            ? 'Within ${AppConstants.bleMaxDistanceMeters.toInt()} m (≈${proximity.estimatedMeters?.toStringAsFixed(0) ?? "?"} m, ${median} dBm)'
            : proximity.showOnDashboard
                ? 'Almost there — move a little closer (${median} dBm, ≈${proximity.estimatedMeters?.toStringAsFixed(0) ?? "?"} m)'
                : 'Too far from teacher (${median} dBm). Move within ${AppConstants.bleMaxDistanceMeters.toInt()} m.',
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
