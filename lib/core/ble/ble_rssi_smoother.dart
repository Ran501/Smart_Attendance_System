import 'dart:math' as math;

/// Rolling RSSI buffer; uses median to ignore single-packet spikes.
class BleRssiSmoother {
  BleRssiSmoother({this.windowSize = 9});

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

  /// Median RSSI, or null if no samples yet.
  int? get median {
    if (_samples.isEmpty) return null;
    final sorted = List<int>.from(_samples)..sort();
    return sorted[sorted.length ~/ 2];
  }

  /// Best (strongest) sample in the window — used when median is borderline.
  int? get peak => _samples.isEmpty ? null : _samples.reduce(math.max);
}
