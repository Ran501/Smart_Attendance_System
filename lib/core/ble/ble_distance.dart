import 'dart:math' as math;

import '../constants/app_constants.dart';

double estimateBleDistanceMeters(int rssi) {
  final ratio = (AppConstants.bleRssiAtOneMeter - rssi) /
      (10 * AppConstants.blePathLossExponent);
  return math.pow(10, ratio).toDouble().clamp(
        0.5,
        AppConstants.bleMaxDistanceMeters + 8,
      );
}
