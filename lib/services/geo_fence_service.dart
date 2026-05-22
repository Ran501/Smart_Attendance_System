import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/constants/app_constants.dart';

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
  Position? _currentPosition; // ✅ FIX: was used but never declared

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

  // ✅ FIX: removed duplicate isInsideRadius — kept single version with optional accuracy params
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

  Future<bool> requestLocationPermission() async {
    final ctx = navigatorKey.currentContext;
    final status = await Permission.location.request();
    if (status.isGranted) {
      // Attendance only needs GPS while the screen is open. Requesting
      // locationAlways causes Android manifest warnings and is unnecessary.
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

  Future<Position?> getCurrentPosition({int retries = 3}) async {
    for (int i = 0; i < retries; i++) {
      try {
        if (!await requestLocationPermission()) return null;

        if (!await isLocationServiceEnabled()) {
          final ctx = navigatorKey.currentContext;
          if (ctx != null && ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              const SnackBar(
                content: Text('Please enable location services'),
                backgroundColor: Colors.orange,
                action: SnackBarAction(
                  label: 'Open Settings',
                  onPressed: Geolocator.openLocationSettings,
                ),
              ),
            );
          }
          return null;
        }

        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        ).timeout(const Duration(seconds: 15));

        _currentPosition = position;
        return position;
      } catch (e) {
        debugPrint('Error getting location (attempt ${i + 1}): $e');
        if (i == retries - 1) return null;
        await Future.delayed(Duration(seconds: i + 1));
      }
    }
    return null;
  }

  // ✅ FIX: added getBestPosition — was called in attendance_session_screen.dart
  Future<Position?> getBestPosition({int maxSamples = 2}) async {
    Position? best;
    for (int i = 0; i < maxSamples; i++) {
      final pos = await getCurrentPosition(retries: 1);
      if (pos == null) continue;
      if (best == null || pos.accuracy < best.accuracy) {
        best = pos;
      }
    }
    return best;
  }

  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }

  Future<Map<String, dynamic>> isWithinCampus() async {
    try {
      final position = await getCurrentPosition();
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
      if (!await isLocationServiceEnabled()) {
        _showErrorDialog('Location services are disabled. Please enable GPS.');
        return false;
      }

      if (!await requestLocationPermission()) {
        _showErrorDialog('Location permission is required for attendance');
        return false;
      }

      _showLoadingDialog('Verifying your location...');
      final campusCheck = await isWithinCampus();

      final ctx = navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        Navigator.of(ctx).pop();
      }

      if (campusCheck['error'] != null) {
        _showErrorDialog(campusCheck['error'] as String);
        return false;
      }

      if (!(campusCheck['withinCampus'] as bool)) {
        _showErrorDialog(
          'You are outside the college campus.\n'
          'Distance from campus: ${campusCheck['distanceText']}\n'
          'Please move within ${(campusRadius / 1000).toStringAsFixed(1)}km of the campus.',
        );
        return false;
      }

      _showSuccessDialog('Location verified! You are within the campus.');
      return true;
    } catch (e) {
      _showErrorDialog('Location verification failed: ${e.toString()}');
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

  void _showLoadingDialog(String message) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(message),
          ],
        ),
      ),
    );
  }

  void _showErrorDialog(String message) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Retry',
          onPressed: () {},
          textColor: Colors.white,
        ),
      ),
    );
  }

  void _showSuccessDialog(String message) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
