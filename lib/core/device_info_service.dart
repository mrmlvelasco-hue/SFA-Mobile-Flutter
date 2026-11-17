import 'dart:io';
import 'dart:math';

import 'api_config.dart';
import 'token_storage.dart';

/// The backend's /login requires deviceId, device_name, lat, lng, ip and
/// app_version on every request (see sfa-api's app/routers/auth.py).
///
/// GPS and real network-IP lookup are deferred per the "core screens
/// online-only first" milestone -- lat/lng/ip are stubbed below. Wire real
/// values in once the geolocation pass happens (see README "Known gaps").
class DeviceInfoService {
  DeviceInfoService._();
  static final DeviceInfoService instance = DeviceInfoService._();

  Future<String> deviceId() async {
    final existing = await TokenStorage.instance.readDeviceId();
    if (existing != null && existing.isNotEmpty) return existing;
    final generated = _uuidV4();
    await TokenStorage.instance.saveDeviceId(generated);
    return generated;
  }

  String deviceName() {
    try {
      return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    } catch (_) {
      return 'flutter-client';
    }
  }

  /// TODO(geolocation pass): replace with a real fix from `geolocator`.
  double latStub() => 0.0;

  /// TODO(geolocation pass): replace with a real fix from `geolocator`.
  double lngStub() => 0.0;

  /// TODO: replace with the device's real public/LAN IP if the backend ever
  /// enforces it; today it is only stored in the audit trail.
  String ipStub() => '0.0.0.0';

  String appVersion() => ApiConfig.appVersion;

  String _uuidV4() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    final h = bytes.map(hex).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }
}
