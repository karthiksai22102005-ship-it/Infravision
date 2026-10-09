import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../config/mobile_config.dart';
import '../core/app_logger.dart';
import '../models/observation.dart';

/// Lifecycle of one high-accuracy acquisition attempt (§20/§22).
enum GpsAcquisitionState { idle, acquiring, acquired, degraded, unavailable }

/// Outcome of the last acquisition attempt — shown verbatim in the UI.
enum GpsOutcome {
  acquired('GPS ready'),
  degraded('Low accuracy'),
  timedOut('Location timed out'),
  permissionDenied('Location permission denied'),
  permissionPermanentlyDenied('Location permission blocked'),
  serviceDisabled('Device location is off'),
  unavailable('Location unavailable');

  const GpsOutcome(this.label);
  final String label;
}

/// Real device location (fused provider / GNSS). Never fabricates values.
///
/// Acquisition strategy implemented here matches §20:
/// permission -> services check -> cached fix -> fresh high-accuracy fix ->
/// several readings compared by accuracy -> best legitimate fix kept ->
/// stream stopped as soon as it is no longer needed (battery §57).
class LocationService extends ChangeNotifier {
  LocationService();

  LocationFix? _best;
  GpsAcquisitionState _state = GpsAcquisitionState.idle;
  GpsOutcome _lastOutcome = GpsOutcome.unavailable;
  String _statusMessage = 'Location not requested yet.';
  int _readingCount = 0;
  int _staleReadings = 0;
  bool _approximatePermission = false;
  bool _serviceEnabled = false;
  StreamSubscription<Position>? _stream;
  Timer? _timeoutTimer;
  DateTime? _lastStreamStop;

  // Getters -----------------------------------------------------------------
  LocationFix? get best => _best;
  GpsAcquisitionState get state => _state;
  GpsOutcome get lastOutcome => _lastOutcome;
  String get statusMessage => _statusMessage;
  int get readingCount => _readingCount;
  bool get approximatePermission => _approximatePermission;
  bool get serviceEnabled => _serviceEnabled;
  bool get hasFix => _best != null;
  DateTime? get lastStreamStoppedAt => _lastStreamStop;

  double? get accuracyMeters => _best?.accuracyMeters;

  /// `±3.2 m` — always derived from what the location API actually reported.
  String get accuracyLabel {
    final LocationFix? fix = _best;
    if (fix == null) return 'No GPS fix';
    return '±${fix.accuracyMeters < 0 ? '?' : fix.accuracyMeters.toStringAsFixed(fix.accuracyMeters < 10 ? 1 : 0)} m';
  }

  String get accuracyGradeLabel {
    final LocationFix? fix = _best;
    if (fix == null) return 'Unavailable';
    final double accuracy = fix.accuracyMeters;
    if (fix.isApproximatePermission) return 'Approximate';
    if (accuracy <= MobileConfig.accuracyExcellentMeters) return 'Excellent';
    if (accuracy <= MobileConfig.accuracyGoodMeters) return 'Good';
    if (accuracy <= MobileConfig.accuracyModerateMeters) return 'Moderate';
    return 'Poor';
  }

  String get formattedCoordinates {
    final LocationFix? fix = _best;
    if (fix == null) return 'Waiting for GPS fix';
    final String latHem = fix.latitude >= 0 ? 'N' : 'S';
    final String lonHem = fix.longitude >= 0 ? 'E' : 'W';
    return '${fix.latitude.abs().toStringAsFixed(5)}° $latHem, '
        '${fix.longitude.abs().toStringAsFixed(5)}° $lonHem';
  }

  /// Permission + services pre-flight (§20 step 1-2, §23, §68).
  Future<GpsOutcome> prepare() async {
    _serviceEnabled = await _guard(() => Geolocator.isLocationServiceEnabled(),
        fallback: false, scope: 'serviceCheck');
    if (!_serviceEnabled) {
      _lastOutcome = GpsOutcome.serviceDisabled;
      _statusMessage = 'Device location is switched off.';
      _state = GpsAcquisitionState.unavailable;
      notifyListeners();
      return _lastOutcome;
    }

    LocationPermission permission = await _guard(
      () => Geolocator.checkPermission(),
      fallback: LocationPermission.denied,
      scope: 'permissionCheck',
    );

    if (permission == LocationPermission.denied) {
      permission = await _guard(
        () => Geolocator.requestPermission(),
        fallback: LocationPermission.denied,
        scope: 'permissionRequest',
      );
    }

    if (permission == LocationPermission.denied) {
      _lastOutcome = GpsOutcome.permissionDenied;
      _statusMessage = 'Location permission denied.';
      _state = GpsAcquisitionState.unavailable;
      notifyListeners();
      return _lastOutcome;
    }
    if (permission == LocationPermission.deniedForever) {
      _lastOutcome = GpsOutcome.permissionPermanentlyDenied;
      _statusMessage = 'Location permission is blocked in Android settings.';
      _state = GpsAcquisitionState.unavailable;
      notifyListeners();
      return _lastOutcome;
    }

    // Android 12+ precise vs approximate location (§23).
    final LocationAccuracyStatus? accuracyStatus = await _guard<
        LocationAccuracyStatus?>(
      () => Geolocator.getLocationAccuracy(),
      fallback: null,
      scope: 'accuracyStatus',
    );
    _approximatePermission = accuracyStatus == LocationAccuracyStatus.reduced;
    if (_approximatePermission) {
      _statusMessage = 'Approximate location enabled.';
    } else {
      _statusMessage = 'Precise location enabled.';
    }
    notifyListeners();
    return GpsOutcome.acquired;
  }
  /// Full acquisition flow with a hard time budget (§20, §22).
  ///
  /// Returns the best *real* fix obtained within the budget. It never invents
  /// coordinates: if nothing usable arrives the outcome is `timedOut`.
  Future<GpsOutcome> acquireBestFix({
    Duration? timeout,
    double targetAccuracyMeters = 12.0,
  }) async {
    final GpsOutcome preparation = await prepare();
    if (preparation != GpsOutcome.acquired) {
      return preparation;
    }

    _state = GpsAcquisitionState.acquiring;
    _readingCount = 0;
    _staleReadings = 0;
    _statusMessage = 'Acquiring location...';
    notifyListeners();

    final Duration budget = timeout ?? MobileConfig.locationAcquisitionTimeout;
    final Completer<GpsOutcome> completer = Completer<GpsOutcome>();

    final Position? cached = await _guard<Position?>(
      () => Geolocator.getLastKnownPosition(),
      fallback: null,
      scope: 'lastKnownPosition',
    );
    if (cached != null && !completer.isCompleted) {
      _consider(cached, 'cached');
      _statusMessage = 'Cached fix $accuracyLabel — improving...';
      notifyListeners();
    }

    try {
      await _stream?.cancel();
      _stream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 0,
        ),
      ).listen(
        (Position position) {
          if (completer.isCompleted) return;
          _consider(position, 'fresh');
          if (_best != null && _best!.accuracyMeters <= targetAccuracyMeters) {
            _complete(completer, GpsOutcome.acquired);
          } else if (_staleReadings >= 3 && _best != null) {
            _complete(completer, _qualityOf(_best!));
          }
        },
        onError: (Object error) {
          AppLog.e('LocationService', 'Position stream error: $error');
          if (!completer.isCompleted) {
            _complete(
              completer,
              _best == null ? GpsOutcome.unavailable : _qualityOf(_best!),
            );
          }
        },
        cancelOnError: false,
      );
    } catch (e) {
      AppLog.e('LocationService', 'Could not start position stream: $e');
    }

    _timeoutTimer = Timer(budget, () {
      if (completer.isCompleted) return;
      if (_best == null) {
        _complete(completer, GpsOutcome.timedOut);
      } else {
        _complete(completer, _qualityOf(_best!));
      }
    });

    final GpsOutcome outcome = await completer.future;
    await stopLiveTracking();

    switch (outcome) {
      case GpsOutcome.acquired:
        _state = GpsAcquisitionState.acquired;
        _statusMessage = 'GPS ready $accuracyLabel (${accuracyGradeLabel.toLowerCase()}).';
        break;
      case GpsOutcome.degraded:
        _state = GpsAcquisitionState.degraded;
        _statusMessage = 'Location accuracy is currently low ($accuracyLabel).';
        break;
      case GpsOutcome.timedOut:
        _state = GpsAcquisitionState.unavailable;
        _statusMessage = 'Could not get a location fix yet.';
        break;
      default:
        _state = GpsAcquisitionState.unavailable;
        _statusMessage = _lastOutcome == GpsOutcome.unavailable
            ? 'Location unavailable.'
            : _lastOutcome.label;
        break;
    }
    _lastOutcome = outcome;
    notifyListeners();
    return outcome;
  }

  GpsOutcome _qualityOf(LocationFix fix) {
    if (fix.accuracyMeters < 0 || fix.accuracyMeters > 150) {
      return GpsOutcome.degraded;
    }
    return fix.accuracyMeters <= MobileConfig.accuracyModerateMeters
        ? GpsOutcome.acquired
        : GpsOutcome.degraded;
  }

  void _complete(Completer<GpsOutcome> completer, GpsOutcome outcome) {
    if (completer.isCompleted) return;
    _lastOutcome = outcome;
    completer.complete(outcome);
  }
  /// Keeps a bounded low-frequency watch alive while the capture screen is
  /// open, then stops itself (§24/§57 — GPS never runs indefinitely).
  Future<void> startWatch({Duration? maxDuration}) async {
    if (_stream != null) return;
    final GpsOutcome preparation = await prepare();
    if (preparation != GpsOutcome.acquired) return;
    try {
      _stream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 4,
        ),
      ).listen(
        (Position position) {
          _consider(position, 'watch');
          notifyListeners();
        },
        onError: (Object error) => AppLog.e('LocationService', 'Watch error: $error'),
      );
      _timeoutTimer = Timer(maxDuration ?? MobileConfig.locationStreamMaxDuration, stopLiveTracking);
    } catch (e) {
      AppLog.e('LocationService', 'Could not start watch: $e');
    }
  }

  /// Cancels the active stream — call whenever a screen is left (§57).
  Future<void> stopLiveTracking() async {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    final StreamSubscription<Position>? subscription = _stream;
    _stream = null;
    if (subscription != null) {
      await subscription.cancel();
      _lastStreamStop = DateTime.now();
      AppLog.d('LocationService', 'Stopped location stream (battery saving)');
    }
  }

  /// Adopts an externally obtained fix (e.g. camera capture association).
  void adopt(Position position, {String source = 'external'}) {
    _consider(position, source);
    notifyListeners();
  }

  void _consider(Position position, String source) {
    _readingCount++;
    final LocationFix fix = LocationFix(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
      timestamp: position.timestamp,
      altitudeMeters: position.altitude,
      headingDegrees: position.heading,
      speedMetersPerSecond: position.speed,
      isMocked: position.isMocked,
      isApproximatePermission: _approximatePermission,
    );

    final LocationFix? current = _best;
    if (current == null) {
      _best = fix;
      _staleReadings = 0;
      return;
    }

    // Accept a clearly better reading, or any reading when the previous one
    // was unusable (negative/unknown accuracy).
    final bool better = fix.accuracyMeters >= 0 &&
        (current.accuracyMeters < 0 ||
            fix.accuracyMeters < current.accuracyMeters * 0.9);
    if (better) {
      _best = fix;
      _staleReadings = 0;
      _statusMessage = 'Improving $accuracyLabel...';
      AppLog.d(
        'LocationService',
        'Better fix from $source: ${fix.accuracyMeters.toStringAsFixed(1)} m',
      );
    } else {
      _staleReadings++;
    }
  }

  Future<void> openAppSettings() => Geolocator.openAppSettings();
  Future<void> openLocationSettings() => Geolocator.openLocationSettings();

  /// Keeps the best known fix (used when restoring state).
  void seed(LocationFix? fix) {
    if (fix == null) return;
    _best = fix;
    _state = GpsAcquisitionState.acquired;
    notifyListeners();
  }

  Future<T> _guard<T>(
    Future<T> Function() action, {
    required T fallback,
    required String scope,
  }) async {
    try {
      return await action();
    } catch (e) {
      AppLog.e('LocationService', '$scope failed: $e');
      return fallback;
    }
  }

  @override
  void dispose() {
    unawaited(stopLiveTracking());
    super.dispose();
  }
}