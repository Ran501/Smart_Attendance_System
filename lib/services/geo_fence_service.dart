import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/constants/app_constants.dart';

/// Result of proximity check (matches backend formula).
class GeoProximityResult {
  final bool valid;
  final double distanceMeters;
  final double allowedRadiusMeters;
  final double baseRadiusMeters;

  const GeoProximityResult({
    required this.valid,
    required this.distanceMeters,
    required this.allowedRadiusMeters,
    required this.baseRadiusMeters,
  });
}

class GeoFenceService {
  static final GeoFenceService _instance = GeoFenceService._internal();
  factory GeoFenceService() => _instance;
  GeoFenceService._internal();

  StreamSubscription<Position>? _positionStream;
  bool _isMonitoring = false;

  static const double campusLatitude = 28.6139;
  static const double campusLongitude = 77.2090;
  static const double campusRadius = 500;

  double _normalizeAccuracy(double? accuracy) {
    if (accuracy == null || accuracy <= 0) {
      return AppConstants.gpsFixedBufferMeters;
    }
    return math.min(accuracy, AppConstants.maxAccuracyBufferMeters);
  }

  double effectiveAllowedRadius({
    double? baseRadius,
    double? hostAccuracy,
    double? studentAccuracy,
  }) {
    final base = baseRadius ?? AppConstants.hostSessionBaseRadiusMeters;
    return base +
        AppConstants.gpsFixedBufferMeters +
        _normalizeAccuracy(hostAccuracy) +
        _normalizeAccuracy(studentAccuracy);
  }

  GeoProximityResult checkHostProximity({
    required double studentLat,
    required double studentLon,
    required double hostLat,
    required double hostLon,
    double? baseRadius,
    double? hostAccuracy,
    double? studentAccuracy,
  }) {
    final distance = Geolocator.distanceBetween(
      studentLat,
      studentLon,
      hostLat,
      hostLon,
    );
    final allowed = effectiveAllowedRadius(
      baseRadius: baseRadius,
      hostAccuracy: hostAccuracy,
      studentAccuracy: studentAccuracy,
    );
    final base = baseRadius ?? AppConstants.hostSessionBaseRadiusMeters;
    return GeoProximityResult(
      valid: distance <= allowed,
      distanceMeters: distance,
      allowedRadiusMeters: allowed,
      baseRadiusMeters: base,
    );
  }

  Future<bool> requestLocationPermission() async {
    final ctx = navigatorKey.currentContext;
    final status = await Permission.location.request();
    if (status.isGranted) {
      if (await Permission.location.isGranted) {
        await Permission.locationAlways.request();
      }
      return true;
    } else if (status.isDenied) {
      if (ctx != null && ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(
            content: Text(
              'Location permission is required for attendance verification',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return false;
    } else if (status.isPermanentlyDenied) {
      openAppSettings();
      return false;
    }
    return false;
  }

  Future<bool> isLocationServiceEnabled() async {
    return Geolocator.isLocationServiceEnabled();
  }

  /// Single quick fix (legacy).
  Future<Position?> getCurrentPosition({int retries = 3}) async {
    return getBestPosition(maxSamples: retries);
  }

  /// Takes several GPS samples and returns the most accurate fix.
  Future<Position?> getBestPosition({int maxSamples = 5}) async {
    if (!await requestLocationPermission()) return null;
    if (!await isLocationServiceEnabled()) return null;

    Position? best;
    for (var i = 0; i < maxSamples; i++) {
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
            timeLimit: Duration(seconds: 12),
          ),
        );
        if (best == null ||
            (position.accuracy > 0 &&
                (best.accuracy <= 0 || position.accuracy < best.accuracy))) {
          best = position;
        }
        if (best.accuracy > 0 && best.accuracy <= 8) break;
      } catch (e) {
        debugPrint('GPS sample ${i + 1} failed: $e');
      }
      if (i < maxSamples - 1) {
        await Future.delayed(Duration(milliseconds: 400 + i * 200));
      }
    }

    return best;
  }

  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }

  bool isInsideRadius({
    required double studentLat,
    required double studentLon,
    required double centerLat,
    required double centerLon,
    required double radiusMeters,
    double? hostAccuracy,
    double? studentAccuracy,
  }) {
    return checkHostProximity(
      studentLat: studentLat,
      studentLon: studentLon,
      hostLat: centerLat,
      hostLon: centerLon,
      baseRadius: radiusMeters,
      hostAccuracy: hostAccuracy,
      studentAccuracy: studentAccuracy,
    ).valid;
  }

  Future<Map<String, dynamic>> isWithinCampus() async {
    try {
      final position = await getBestPosition();
      if (position == null) {
        return {
          'withinCampus': false,
          'error': 'Could not get your location',
          'distance': null,
        };
      }

      final distance = calculateDistance(
        position.latitude,
        position.longitude,
        campusLatitude,
        campusLongitude,
      );

      return {
        'withinCampus': distance <= campusRadius,
        'distance': distance,
        'distanceText': _formatDistance(distance),
        'location': {
          'latitude': position.latitude,
          'longitude': position.longitude,
        },
        'error': null,
      };
    } catch (e) {
      return {
        'withinCampus': false,
        'error': 'Failed to verify location: ${e.toString()}',
        'distance': null,
      };
    }
  }

  Future<bool> validateLocationForAttendance() async {
    try {
      if (!await isLocationServiceEnabled()) return false;
      if (!await requestLocationPermission()) return false;
      final campusCheck = await isWithinCampus();
      return campusCheck['withinCampus'] == true;
    } catch (_) {
      return false;
    }
  }

  void startLocationMonitoring(Function(Position) onLocationChanged) {
    if (_isMonitoring) return;
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      ),
    ).listen(onLocationChanged);
    _isMonitoring = true;
  }

  void stopLocationMonitoring() {
    _positionStream?.cancel();
    _isMonitoring = false;
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(2)} km';
    }
    return '${meters.toStringAsFixed(0)} meters';
  }
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
