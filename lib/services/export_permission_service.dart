import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Android storage permissions for report export.
class ExportPermissionService {
  /// Required only for direct file writes on Android 9 and below.
  static Future<bool> ensureGrantedForLegacyWrite() async {
    if (kIsWeb || !Platform.isAndroid) return true;

    final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    if (sdk >= 30) return true;

    return _requestStorage(required: true);
  }

  /// Best-effort permission prompts; does not block MediaStore on Android 10+.
  static Future<void> requestBestEffort() async {
    if (kIsWeb || !Platform.isAndroid) return;

    final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    if (sdk >= 33) {
      await [
        Permission.storage,
        Permission.photos,
        Permission.videos,
        Permission.audio,
      ].request();
      return;
    }

    await Permission.storage.request();
  }

  static Future<bool> _requestStorage({required bool required}) async {
    var status = await Permission.storage.status;
    if (status.isGranted || status.isLimited) return true;

    status = await Permission.storage.request();
    if (status.isGranted || status.isLimited) return true;

    if (required && status.isPermanentlyDenied) {
      await openAppSettings();
    }
    return !required || status.isGranted || status.isLimited;
  }
}
