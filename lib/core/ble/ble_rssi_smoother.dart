import 'dart:math' as math;

import '../constants/app_constants.dart';

/// Rolling RSSI buffer; median + peak for fast, stable proximity.
class BleRssiSmoother {
  BleRssiSmoother({int? windowSize})
      : windowSize = windowSize ?? AppConstants.bleRssiMedianWindow;

  final int windowSize;
  final List<int> _samples = [];

  void add(int rssi) {
    _samples.add(rssi);
    while (_samples.length > windowSize) {
      _samples.removeAt(0);
    }
  }

  void clear() => _samples.clear();

  bool get hasSamples => _samples.isNotEmpty;

  int? get median {
    if (_samples.isEmpty) return null;
    final sorted = List<int>.from(_samples)..sort();
    return sorted[sorted.length ~/ 2];
  }

  int? get peak => _samples.isEmpty ? null : _samples.reduce(math.max);

  /// Best estimate for gating: strongest recent reading (fast when close).
  int? get effectiveRssi {
    if (_samples.isEmpty) return null;
    final m = median!;
    final p = peak!;
    return math.max(m, p);
  }
}
