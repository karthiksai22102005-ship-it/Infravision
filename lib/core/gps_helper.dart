import 'package:geolocator/geolocator.dart';

/// Resolves device GPS coordinates for evidence binding (desktop + mobile).
class GpsHelper {
  GpsHelper._();

  static const String defaultCoordinates = '17.3850° N, 78.4867° E';

  /// A resolved numeric position (null when unavailable / denied).
  static Future<Position?> getPosition() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<String> getCoordinatesString() async {
    final pos = await getPosition();
    if (pos == null) return defaultCoordinates;
    final latHem = pos.latitude >= 0 ? 'N' : 'S';
    final lonHem = pos.longitude >= 0 ? 'E' : 'W';
    return '${pos.latitude.abs().toStringAsFixed(4)}° $latHem, ${pos.longitude.abs().toStringAsFixed(4)}° $lonHem';
  }

  /// Resolves {lat, lon} numbers for distance computation / map placement.
  static Future<({double lat, double lon})?> getLatLng() async {
    final pos = await getPosition();
    if (pos == null) return null;
    return (lat: pos.latitude, lon: pos.longitude);
  }
}
