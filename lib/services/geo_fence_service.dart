import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/constants/app_constants.dart';

class GeoFenceService {
  static final GeoFenceService _instance = GeoFenceService._internal();
  factory GeoFenceService() => _instance;
  GeoFenceService._internal();

  StreamSubscription<Position>? _positionStream;
  bool _isMonitoring = false;
  Position? _currentPosition;

  // College campus boundaries (example - replace with actual coordinates)
  static const double campusLatitude =
      28.6139; // Replace with your college latitude
  static const double campusLongitude =
      77.2090; // Replace with your college longitude
  static const double campusRadius = 500; // Radius in meters

  // Check and request location permissions
  Future<bool> requestLocationPermission() async {
    final status = await Permission.location.request();

    if (status.isGranted) {
      // Also request background location for Android
      if (await Permission.location.isGranted) {
        await Permission.locationAlways.request();
      }
      return true;
    } else if (status.isDenied) {
      ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
        const SnackBar(
          content: Text(
            'Location permission is required for attendance verification',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return false;
    } else if (status.isPermanentlyDenied) {
      openAppSettings();
      return false;
    }
    return false;
  }

  // Check if location services are enabled
  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  // Get current position with retry logic
  Future<Position?> getCurrentPosition({int retries = 3}) async {
    for (int i = 0; i < retries; i++) {
      try {
        // Check permissions first
        if (!await requestLocationPermission()) {
          return null;
        }

        // Check if location services are enabled
        if (!await isLocationServiceEnabled()) {
          ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
            const SnackBar(
              content: Text('Please enable location services'),
              backgroundColor: Colors.orange,
              action: SnackBarAction(
                label: 'Open Settings',
                onPressed: Geolocator.openLocationSettings,
              ),
            ),
          );
          return null;
        }

        // Get position with timeout
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

  // Calculate distance between two coordinates
  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }

  // Check if user is within campus geofence
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

      final withinCampus = distance <= campusRadius;

      return {
        'withinCampus': withinCampus,
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

  // Validate location for attendance
  Future<bool> validateLocationForAttendance() async {
    try {
      // First check if location services are enabled
      if (!await isLocationServiceEnabled()) {
        _showErrorDialog('Location services are disabled. Please enable GPS.');
        return false;
      }

      // Check permissions
      if (!await requestLocationPermission()) {
        _showErrorDialog('Location permission is required for attendance');
        return false;
      }

      // Get location with loading indicator
      _showLoadingDialog('Verifying your location...');

      final campusCheck = await isWithinCampus();
      Navigator.of(navigatorKey.currentContext!).pop(); // Close loading dialog

      if (campusCheck['error'] != null) {
        _showErrorDialog(campusCheck['error']);
        return false;
      }

      if (!campusCheck['withinCampus']) {
        _showErrorDialog(
          'You are outside the college campus.\n'
          'Distance from campus: ${campusCheck['distanceText']}\n'
          'Please move within ${(campusRadius / 1000).toStringAsFixed(1)}km of the campus.',
        );
        return false;
      }

      // Success - within campus
      _showSuccessDialog('Location verified! You are within the campus.');
      return true;
    } catch (e) {
      _showErrorDialog('Location verification failed: ${e.toString()}');
      return false;
    }
  }

  // Start monitoring location changes
  void startLocationMonitoring(Function(Position) onLocationChanged) {
    if (_isMonitoring) return;

    _positionStream =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10, // Update every 10 meters
          ),
        ).listen((position) {
          _currentPosition = position;
          onLocationChanged(position);
        });

    _isMonitoring = true;
  }

  // Stop monitoring
  void stopLocationMonitoring() {
    _positionStream?.cancel();
    _isMonitoring = false;
  }

  // Helper methods
  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(2)} km';
    }
    return '${meters.toStringAsFixed(0)} meters';
  }

  void _showLoadingDialog(String message) {
    showDialog(
      context: navigatorKey.currentContext!,
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
    ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
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
    ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

// Global navigator key for showing dialogs without context
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
