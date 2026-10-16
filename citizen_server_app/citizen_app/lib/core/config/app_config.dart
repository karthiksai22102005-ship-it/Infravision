import 'dart:io';

class AppConfig {
  /// Build-time define: flutter run --dart-define=API_BASE_URL=http://192.168.1.50:8000
  /// 10.0.2.2 is the Android emulator's alias for the host machine.
  /// A physical phone on the same Wi-Fi requires the host computer's LAN IP or a public HTTPS URL.
  static const _configuredApiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static String get defaultApiBaseUrl {
    if (_configuredApiBaseUrl.isNotEmpty) return _configuredApiBaseUrl;
    return Platform.isAndroid
        ? 'http://10.0.2.2:8000'
        : 'http://127.0.0.1:8000';
  }

  static String? _customApiBaseUrl;

  /// Returns the custom runtime API URL if configured, otherwise the build default.
  static String get apiBaseUrl => _customApiBaseUrl ?? defaultApiBaseUrl;

  static set customApiBaseUrl(String? url) {
    if (url == null || url.trim().isEmpty) {
      _customApiBaseUrl = null;
    } else {
      _customApiBaseUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    }
  }

  static const maxPhotos = 5;
  static const maxPhotoBytes = 8 * 1024 * 1024;
  static const goodAccuracyMeters = 50.0;
}
