import '../constants/app_constants.dart';
import 'ble_distance.dart';

/// Proximity band for UI and gating.
enum BleProximityBand {
  /// No beacon or signal too weak.
  outOfRange,

  /// Beacon seen but below "show session" threshold (moving closer).
  weak,

  /// Within ~10 m — show session on dashboard.
  nearby,

  /// Strong signal — safe to mark attendance.
  readyToMark,
}

class BleSessionProximity {
  final String sessionId;
  final BleProximityBand band;
  final int? smoothedRssi;
  final double? estimatedMeters;
  final bool showOnDashboard;
  final bool readyToMark;

  const BleSessionProximity({
    required this.sessionId,
    required this.band,
    this.smoothedRssi,
    this.estimatedMeters,
    required this.showOnDashboard,
    required this.readyToMark,
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
    if (!wasShowing &&
        smoothedRssi >= AppConstants.bleRssiShowSessionEnter) {
      show = true;
    } else if (wasShowing &&
        smoothedRssi < AppConstants.bleRssiShowSessionLeave) {
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

  /// Show session card while approaching or in range (mark still gated by [readyToMark]).
  bool get visibleOnDashboard =>
      showOnDashboard || band == BleProximityBand.weak;

  String get bandLabel {
    switch (band) {
      case BleProximityBand.readyToMark:
        return 'Strong signal · ready';
      case BleProximityBand.nearby:
        return 'Within ${AppConstants.bleMaxDistanceMeters.toInt()} m';
      case BleProximityBand.weak:
        return 'Weak signal · move closer';
      case BleProximityBand.outOfRange:
        return 'Out of range';
    }
  }
}
