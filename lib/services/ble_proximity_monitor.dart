import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../core/ble/ble_proximity_state.dart';
import '../core/ble/ble_rssi_smoother.dart';
import '../core/ble/ble_session_beacon.dart';
import '../core/constants/app_constants.dart';
import 'bluetooth_validation_service.dart';

/// Live BLE proximity with sticky in-range latch (no flicker when moving).
class BleProximityMonitor {
  BleProximityMonitor._();
  static final BleProximityMonitor instance = BleProximityMonitor._();

  final _smoothers = <String, BleRssiSmoother>{};
  final _wasShowing = <String, bool>{};
  final _wasReady = <String, bool>{};
  final _lastInRangeAt = <String, DateTime>{};
  final _lastReadyAt = <String, DateTime>{};
  final _lastRssi = <String, int>{};
  final _latchedInRange = <String, bool>{};

  final _stateController =
      StreamController<Map<String, BleSessionProximity>>.broadcast();

  Stream<Map<String, BleSessionProximity>> get stream => _stateController.stream;

  StreamSubscription<List<ScanResult>>? _scanSub;
  Timer? _holdTick;
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
    final idsChanged = ids.join(',') != _sessionIds.join(',');
    _sessionIds = ids;
    for (final id in ids) {
      if (idsChanged) {
        _smoothers[id] = BleRssiSmoother();
        _wasShowing[id] = false;
        _wasReady[id] = false;
        _latchedInRange[id] = false;
        _lastInRangeAt.remove(id);
        _lastReadyAt.remove(id);
        _lastRssi.remove(id);
      } else {
        _smoothers.putIfAbsent(id, () => BleRssiSmoother());
        _wasShowing.putIfAbsent(id, () => false);
        _wasReady.putIfAbsent(id, () => false);
        _latchedInRange.putIfAbsent(id, () => false);
      }
    }
    _emit();
    if (ids.isEmpty) {
      await stop();
      return;
    }
    if (!_running) {
      await start();
    } else if (idsChanged) {
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
      await FlutterBluePlus.startScan(
        androidScanMode: AndroidScanMode.lowLatency,
        continuousUpdates: true,
      );
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
    _holdTick ??= Timer.periodic(const Duration(seconds: 2), (_) => _emit());

    await FlutterBluePlus.startScan(
      androidScanMode: AndroidScanMode.lowLatency,
      continuousUpdates: true,
    );
  }

  Future<void> stop() async {
    _running = false;
    await _scanSub?.cancel();
    _scanSub = null;
    _holdTick?.cancel();
    _holdTick = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
  }

  void _onScanResults(List<ScanResult> results) {
    final now = DateTime.now();
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
      final id = entry.key;
      final rssi = entry.value;
      _smoothers.putIfAbsent(id, () => BleRssiSmoother()).add(rssi);
      _lastRssi[id] = rssi;

      if (rssi >= AppConstants.bleRssiShowSessionEnter) {
        _lastInRangeAt[id] = now;
        _latchedInRange[id] = true;
      }
      if (rssi >= AppConstants.bleRssiMarkEnter) {
        _lastReadyAt[id] = now;
      }
    }

    _emit();
  }

  bool _withinHold(DateTime? lastAt, int holdSeconds) {
    if (lastAt == null) return false;
    return DateTime.now().difference(lastAt) <
        Duration(seconds: holdSeconds);
  }

  void _maybeClearLatch(String sessionId, int? rssi) {
    if (_latchedInRange[sessionId] != true) return;
    final last = _lastInRangeAt[sessionId];
    if (last == null) return;

    final silentTooLong = !_withinHold(last, AppConstants.bleSessionHoldSeconds);
    final clearlyFar =
        rssi != null && rssi < AppConstants.bleRssiShowSessionLeave;
    final farTooLong = clearlyFar &&
        DateTime.now().difference(last) > const Duration(seconds: 20);

    if (silentTooLong || farTooLong) {
      _latchedInRange[sessionId] = false;
      _wasShowing[sessionId] = false;
      _wasReady[sessionId] = false;
      _lastReadyAt.remove(sessionId);
    }
  }

  BleSessionProximity _stateFor(String sessionId) {
    final smoother = _smoothers[sessionId];
    final rssi = smoother?.effectiveRssi ?? _lastRssi[sessionId];

    _maybeClearLatch(sessionId, rssi);

    final holdRange = _latchedInRange[sessionId] == true &&
        _withinHold(_lastInRangeAt[sessionId], AppConstants.bleSessionHoldSeconds);
    final holdMark = _withinHold(
      _lastReadyAt[sessionId],
      AppConstants.bleMarkHoldSeconds,
    );

    if (rssi == null && !holdRange) {
      return BleSessionProximity.outOfRange(sessionId);
    }

    final useRssi = rssi ?? _lastRssi[sessionId] ?? AppConstants.bleRssiShowSessionEnter;

    if (holdRange) {
      final show = true;
      final ready = holdMark ||
          useRssi >= AppConstants.bleRssiMarkEnter ||
          (_wasReady[sessionId] ?? false);
      _wasShowing[sessionId] = true;
      _wasReady[sessionId] = ready;
      final base = BleSessionProximity.fromRssi(
        sessionId: sessionId,
        smoothedRssi: useRssi,
        wasShowing: true,
        wasReady: ready,
      );
      return base.withHold(show: show, ready: ready);
    }

    final state = BleSessionProximity.fromRssi(
      sessionId: sessionId,
      smoothedRssi: useRssi,
      wasShowing: _wasShowing[sessionId] ?? false,
      wasReady: _wasReady[sessionId] ?? false,
    );
    _wasShowing[sessionId] = state.showOnDashboard;
    _wasReady[sessionId] = state.readyToMark;
    if (state.showOnDashboard) {
      _latchedInRange[sessionId] = true;
      _lastInRangeAt[sessionId] = DateTime.now();
    }
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
