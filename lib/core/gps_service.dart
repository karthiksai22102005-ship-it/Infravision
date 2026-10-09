import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

enum GpsAccuracyGrade {
  excellent, // <= 5 meters
  good,      // <= 15 meters
  moderate,  // <= 30 meters
  poor,      // > 30 meters
  approximate,
  unavailable,
}

/// Robust, real-device GPS and GNSS location service.
///
/// Never fabricates fake coordinates. Obtains high-accuracy position from
/// device GNSS/Fused Location Provider, tracks accuracy in meters, altitude,
/// heading, speed, and handles approximate/precise location permissions cleanly.
class GpsService extends ChangeNotifier {
  GpsService._();
  static final GpsService instance = GpsService._();

  Position? _currentPosition;
  bool _isAcquiring = false;
  String? _statusMessage;
  String? _errorMessage;
  StreamSubscription<Position>? _positionStreamSub;
  DateTime? _lastAcquiredTime;
  bool _isLocationServiceEnabled = false;
  LocationPermission _permission = LocationPermission.denied;

  // Getters
  Position? get currentPosition => _currentPosition;
  bool get isAcquiring => _isAcquiring;
  String? get statusMessage => _statusMessage;
  String? get errorMessage => _errorMessage;
  DateTime? get lastAcquiredTime => _lastAcquiredTime;
  bool get isLocationServiceEnabled => _isLocationServiceEnabled;
  LocationPermission get permission => _permission;

  double? get latitude => _currentPosition?.latitude;
  double? get longitude => _currentPosition?.longitude;
  double? get accuracy => _currentPosition?.accuracy;
  double? get altitude => _currentPosition?.altitude;
  double? get speed => _currentPosition?.speed;
  double? get heading => _currentPosition?.heading;

  bool get hasValidFix => _currentPosition != null;

  GpsAccuracyGrade get accuracyGrade {
    final pos = _currentPosition;
    if (pos == null) return GpsAccuracyGrade.unavailable;
    if (pos.isMocked) return GpsAccuracyGrade.poor;
    final acc = pos.accuracy;
    if (acc <= 5.0) return GpsAccuracyGrade.excellent;
    if (acc <= 15.0) return GpsAccuracyGrade.good;
    if (acc <= 30.0) return GpsAccuracyGrade.moderate;
    if (acc > 30.0) return GpsAccuracyGrade.poor;
    return GpsAccuracyGrade.approximate;
  }

  String get accuracyLabel {
    final pos = _currentPosition;
    if (pos == null) return 'No GPS Fix';
    final acc = pos.accuracy;
    return '±${acc.toStringAsFixed(1)} m (${accuracyGrade.name.toUpperCase()})';
  }

  String get formattedCoordinates {
    final pos = _currentPosition;
    if (pos == null) return 'Location pending GPS fix...';
    final latHem = pos.latitude >= 0 ? 'N' : 'S';
    final lonHem = pos.longitude >= 0 ? 'E' : 'W';
    return '${pos.latitude.abs().toStringAsFixed(5)}° $latHem, ${pos.longitude.abs().toStringAsFixed(5)}° $lonHem';
  }

  /// Starts live high-accuracy location acquisition.
  Future<Position?> acquireBestFix({Duration timeout = const Duration(seconds: 12)}) async {
    _isAcquiring = true;
    _errorMessage = null;
    _statusMessage = 'Checking location services...';
    notifyListeners();

    try {
      // 1. Check if location services are enabled on device
      _isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!_isLocationServiceEnabled) {
        _statusMessage = 'Device location is disabled.';
        _errorMessage = 'Please enable GPS / Location in Android settings.';
        _isAcquiring = false;
        notifyListeners();
        return null;
      }

      // 2. Check and request location permissions
      _permission = await Geolocator.checkPermission();
      if (_permission == LocationPermission.denied) {
        _permission = await Geolocator.requestPermission();
      }

      if (_permission == LocationPermission.denied) {
        _errorMessage = 'Location permission was denied by user.';
        _statusMessage = 'Location permission denied.';
        _isAcquiring = false;
        notifyListeners();
        return null;
      }

      if (_permission == LocationPermission.deniedForever) {
        _errorMessage = 'Location permission is permanently denied. Open app settings to enable.';
        _statusMessage = 'Permission permanently denied.';
        _isAcquiring = false;
        notifyListeners();
        return null;
      }

      // 3. Immediately grab last known location for rapid initial UX
      try {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null && _currentPosition == null) {
          _currentPosition = lastKnown;
          _lastAcquiredTime = lastKnown.timestamp;
          _statusMessage = 'Cached fix (±${lastKnown.accuracy.toStringAsFixed(0)} m)... improving';
          notifyListeners();
        }
      } catch (_) {}

      // 4. Request high-accuracy fresh fix from GNSS / Fused Location
      _statusMessage = 'Acquiring high-accuracy GNSS fix...';
      notifyListeners();

      final freshPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 1,
          timeLimit: Duration(seconds: 10),
        ),
      );

      _currentPosition = freshPosition;
      _lastAcquiredTime = freshPosition.timestamp;
      _statusMessage = 'GPS Ready (±${freshPosition.accuracy.toStringAsFixed(1)} m)';
      _errorMessage = null;
      _isAcquiring = false;
      notifyListeners();
      return freshPosition;
    } on TimeoutException {
      if (_currentPosition != null) {
        _statusMessage = 'Using latest fix (±${_currentPosition!.accuracy.toStringAsFixed(1)} m)';
      } else {
        _errorMessage = 'GPS timeout — weak satellite signal.';
        _statusMessage = 'Location acquisition timed out.';
      }
      _isAcquiring = false;
      notifyListeners();
      return _currentPosition;
    } catch (e) {
      _errorMessage = 'GPS acquisition error: $e';
      _statusMessage = 'Location unavailable';
      _isAcquiring = false;
      notifyListeners();
      return _currentPosition;
    }
  }

  /// Start live position streaming during viewfinder.
  void startLiveTracking() {
    if (_positionStreamSub != null) return;

    try {
      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
      );

      _positionStreamSub = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
        (position) {
          _currentPosition = position;
          _lastAcquiredTime = position.timestamp;
          _errorMessage = null;
          notifyListeners();
        },
        onError: (err) {
          debugPrint('Live GPS stream error: $err');
        },
      );
    } catch (e) {
      debugPrint('Error starting GPS stream: $e');
    }
  }

  /// Stop live streaming to save device battery.
  void stopLiveTracking() {
    _positionStreamSub?.cancel();
    _positionStreamSub = null;
  }

  /// Open device app settings.
  Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  /// Open device location settings.
  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  @override
  void dispose() {
    stopLiveTracking();
    super.dispose();
  }
}
