import 'package:geolocator/geolocator.dart';
import 'gps_service.dart';

/// Compatibility helper and delegate to [GpsService].
class GpsHelper {
  GpsHelper._();

  /// Default fallback text when no GPS fix is available yet (never fake coordinates).
  static const String defaultCoordinates = 'Location pending GPS fix...';

  /// A resolved numeric position from device hardware.
  static Future<Position?> getPosition() async {
    return await GpsService.instance.acquireBestFix();
  }

  /// Formatted coordinates string.
  static Future<String> getCoordinatesString() async {
    final pos = await GpsService.instance.acquireBestFix();
    if (pos == null) return defaultCoordinates;
    final latHem = pos.latitude >= 0 ? 'N' : 'S';
    final lonHem = pos.longitude >= 0 ? 'E' : 'W';
    return '${pos.latitude.abs().toStringAsFixed(5)}° $latHem, ${pos.longitude.abs().toStringAsFixed(5)}° $lonHem';
  }

  /// Resolves {lat, lon} numbers for distance computation / map placement.
  static Future<({double lat, double lon})?> getLatLng() async {
    final pos = await GpsService.instance.acquireBestFix();
    if (pos == null) return null;
    return (lat: pos.latitude, lon: pos.longitude);
  }
}
