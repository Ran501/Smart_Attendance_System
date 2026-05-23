import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../core/ble/ble_proximity_state.dart';
import '../core/ble/ble_rssi_smoother.dart';
import '../core/ble/ble_session_beacon.dart';
import 'bluetooth_validation_service.dart';

/// Live BLE proximity: continuous scan + median RSSI + hysteresis.
class BleProximityMonitor {
  BleProximityMonitor._();
  static final BleProximityMonitor instance = BleProximityMonitor._();

  final _smoothers = <String, BleRssiSmoother>{};
  final _wasShowing = <String, bool>{};
  final _wasReady = <String, bool>{};
  final _stateController =
      StreamController<Map<String, BleSessionProximity>>.broadcast();

  Stream<Map<String, BleSessionProximity>> get stream => _stateController.stream;

  StreamSubscription<List<ScanResult>>? _scanSub;
  List<String> _sessionIds = [];
  bool _running = false;

  Map<String, BleSessionProximity> get currentState {
    final map = <String, BleSessionProximity>{};
    for (final id in _sessionIds) {
      map[id] = _stateFor(id);
    }
    return map;
  }

  Future<void> setSessionIds(List<String> sessionIds) async {
    final ids = sessionIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    _sessionIds = ids;
    for (final id in ids) {
      _smoothers.putIfAbsent(id, () => BleRssiSmoother());
      _wasShowing.putIfAbsent(id, () => false);
      _wasReady.putIfAbsent(id, () => false);
    }
    _emit();
    if (ids.isEmpty) {
      await stop();
      return;
    }
    if (!_running) {
      await start();
    }
  }

  Future<void> start() async {
    if (kIsWeb || _sessionIds.isEmpty) return;
    if (_running) return;

    final ok = await BluetoothValidationService().ensurePermissions();
    if (!ok) return;

    final adapter = await FlutterBluePlus.adapterState.first;
    if (adapter != BluetoothAdapterState.on) return;

    _running = true;
    _scanSub = FlutterBluePlus.scanResults.listen(_onScanResults);

    await FlutterBluePlus.startScan(
      androidScanMode: AndroidScanMode.lowLatency,
      continuousUpdates: true,
    );
  }

  Future<void> stop() async {
    _running = false;
    await _scanSub?.cancel();
    _scanSub = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
  }

  void _onScanResults(List<ScanResult> results) {
    final bestRaw = <String, int>{};
    for (final result in results) {
      for (final id in _sessionIds) {
        if (!BleSessionBeacon.advertisementMatches(
          result.advertisementData,
          id,
        )) {
          continue;
        }
        final prev = bestRaw[id];
        if (prev == null || result.rssi > prev) {
          bestRaw[id] = result.rssi;
        }
      }
    }

    for (final entry in bestRaw.entries) {
      _smoothers.putIfAbsent(entry.key, () => BleRssiSmoother()).add(entry.value);
    }

    _emit();
  }

  BleSessionProximity _stateFor(String sessionId) {
    final smoother = _smoothers[sessionId];
    final median = smoother?.median;
    if (median == null) {
      return BleSessionProximity.outOfRange(sessionId);
    }

    final state = BleSessionProximity.fromRssi(
      sessionId: sessionId,
      smoothedRssi: median,
      wasShowing: _wasShowing[sessionId] ?? false,
      wasReady: _wasReady[sessionId] ?? false,
    );
    _wasShowing[sessionId] = state.showOnDashboard;
    _wasReady[sessionId] = state.readyToMark;
    return state;
  }

  void _emit() {
    if (_stateController.isClosed) return;
    _stateController.add(currentState);
  }

  void dispose() {
    stop();
    _stateController.close();
  }
}
