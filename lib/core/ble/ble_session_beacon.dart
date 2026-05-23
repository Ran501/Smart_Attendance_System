import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Shared BLE payload for teacher beacon ↔ student scan (Android + iOS).
class BleSessionBeacon {
  BleSessionBeacon._();

  /// GATT service UUID advertised during attendance sessions.
  static final Guid serviceGuid = Guid('6f6e6500-0000-1000-8000-00805f9b34fb');

  /// Manufacturer ID (test range — not a registered SIG ID).
  static const int manufacturerId = 0xFACE;

  static const List<int> _magic = [0x46, 0x50, 0x53]; // "FPS"

  static String displayName(String sessionId) => 'FacePass-$sessionId';

  static Uint8List encodePayload(String sessionId) {
    final id = sessionId.trim();
    return Uint8List.fromList([..._magic, ...utf8.encode(id)]);
  }

  static bool payloadContainsSession(List<int> bytes, String sessionId) {
    if (bytes.isEmpty || sessionId.trim().isEmpty) return false;
    if (bytes.length >= _magic.length) {
      var ok = true;
      for (var i = 0; i < _magic.length; i++) {
        if (bytes[i] != _magic[i]) {
          ok = false;
          break;
        }
      }
      if (ok) {
        final embedded = utf8.decode(bytes.sublist(_magic.length), allowMalformed: true);
        return embedded.toLowerCase() == sessionId.trim().toLowerCase();
      }
    }
    final text = utf8.decode(bytes, allowMalformed: true).toLowerCase();
    final id = sessionId.trim().toLowerCase();
    return text.contains(id);
  }

  static bool advertisementMatches(AdvertisementData ad, String sessionId) {
    for (final data in ad.manufacturerData.values) {
      if (payloadContainsSession(data, sessionId)) return true;
    }
    for (final data in ad.serviceData.values) {
      if (payloadContainsSession(data, sessionId)) return true;
    }

    final name = ad.advName.isNotEmpty ? ad.advName : '';
    if (name.isNotEmpty) {
      final expected = displayName(sessionId);
      if (name.toLowerCase() == expected.toLowerCase()) return true;
      if (name.toLowerCase().contains(sessionId.trim().toLowerCase())) {
        return true;
      }
    }

    return false;
  }
}
