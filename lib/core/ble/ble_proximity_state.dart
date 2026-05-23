import '../constants/app_constants.dart';
import 'ble_distance.dart';

/// Proximity band for UI and gating.
enum BleProximityBand {
  outOfRange,
  weak,
  nearby,
  readyToMark,
}

class BleSessionProximity {
  final String sessionId;
  final BleProximityBand band;
  final int? smoothedRssi;
  final double? estimatedMeters;
  final bool showOnDashboard;
  final bool readyToMark;
  final bool heldInRange;

  const BleSessionProximity({
    required this.sessionId,
    required this.band,
    this.smoothedRssi,
    this.estimatedMeters,
    required this.showOnDashboard,
    required this.readyToMark,
    this.heldInRange = false,
  });

  static BleSessionProximity outOfRange(String sessionId) => BleSessionProximity(
        sessionId: sessionId,
        band: BleProximityBand.outOfRange,
        showOnDashboard: false,
        readyToMark: false,
      );

  factory BleSessionProximity.fromRssi({
    required String sessionId,
    required int smoothedRssi,
    required bool wasShowing,
    required bool wasReady,
  }) {
    final meters = estimateBleDistanceMeters(smoothedRssi);

    var show = wasShowing;
    if (!wasShowing && smoothedRssi >= AppConstants.bleRssiShowSessionEnter) {
      show = true;
    } else if (wasShowing && smoothedRssi < AppConstants.bleRssiShowSessionLeave) {
      show = false;
    }

    var ready = wasReady;
    if (!wasReady && smoothedRssi >= AppConstants.bleRssiMarkEnter) {
      ready = true;
    } else if (wasReady && smoothedRssi < AppConstants.bleRssiMarkLeave) {
      ready = false;
    }

    BleProximityBand band;
    if (ready) {
      band = BleProximityBand.readyToMark;
    } else if (show) {
      band = BleProximityBand.nearby;
    } else if (smoothedRssi >= AppConstants.bleRssiShowSessionLeave) {
      band = BleProximityBand.weak;
    } else {
      band = BleProximityBand.outOfRange;
    }

    return BleSessionProximity(
      sessionId: sessionId,
      band: band,
      smoothedRssi: smoothedRssi,
      estimatedMeters: meters,
      showOnDashboard: show,
      readyToMark: ready,
    );
  }

  BleSessionProximity withHold({
    required bool show,
    required bool ready,
  }) {
    BleProximityBand band;
    if (ready) {
      band = BleProximityBand.readyToMark;
    } else if (show) {
      band = BleProximityBand.nearby;
    } else {
      band = BleProximityBand.outOfRange;
    }
    return BleSessionProximity(
      sessionId: sessionId,
      band: band,
      smoothedRssi: smoothedRssi,
      estimatedMeters: estimatedMeters,
      showOnDashboard: show,
      readyToMark: ready,
      heldInRange: true,
    );
  }

  /// Stable dashboard visibility (no flicker when moving phone).
  bool get visibleOnDashboard => showOnDashboard;

  /// Can tap Mark attendance while session is visible (server re-checks BLE on submit).
  bool get canMarkAttendance => showOnDashboard;

  String get bandLabel {
    if (heldInRange && readyToMark) {
      return 'Within ${AppConstants.bleMaxDistanceMeters.toInt()} m · ready';
    }
    switch (band) {
      case BleProximityBand.readyToMark:
        return 'Within ${AppConstants.bleMaxDistanceMeters.toInt()} m · ready';
      case BleProximityBand.nearby:
        return heldInRange
            ? 'Within ${AppConstants.bleMaxDistanceMeters.toInt()} m'
            : 'Within ${AppConstants.bleMaxDistanceMeters.toInt()} m';
      case BleProximityBand.weak:
        return 'Within ${AppConstants.bleMaxDistanceMeters.toInt()} m';
      case BleProximityBand.outOfRange:
        return 'Out of range';
    }
  }
}
