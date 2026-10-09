import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/app_logger.dart';

/// One selectable zoom level that the *device actually supports* (§9).
class ZoomPreset {
  const ZoomPreset(this.factor, this.label);

  final double factor;
  final String label;
}

/// Static capability description of the device camera hardware (§8).
class CameraCapabilities {
  const CameraCapabilities({
    required this.cameras,
    required this.hasRear,
    required this.hasFront,
    required this.hasFlash,
    required this.minZoom,
    required this.maxZoom,
    this.presets = const <ZoomPreset>[],
  });

  static const CameraCapabilities empty = CameraCapabilities(
    cameras: <CameraDescription>[],
    hasRear: false,
    hasFront: false,
    hasFlash: false,
    minZoom: 1,
    maxZoom: 1,
  );

  final List<CameraDescription> cameras;
  final bool hasRear;
  final bool hasFront;
  final bool hasFlash;
  final double minZoom;
  final double maxZoom;
  final List<ZoomPreset> presets;

  bool get hasMultiple => cameras.length > 1;
}

/// Result of a still capture (§13).
class CameraCapture {
  const CameraCapture({
    required this.file,
    required this.capturedAt,
    required this.isFrontFacing,
    required this.zoomFactor,
  });

  final File file;
  final DateTime capturedAt;
  final bool isFrontFacing;
  final double zoomFactor;
}

/// Result of a video capture (§16).
class CameraVideoCapture {
  const CameraVideoCapture({
    required this.file,
    required this.capturedAt,
    required this.duration,
    required this.isFrontFacing,
  });

  final File file;
  final DateTime capturedAt;
  final Duration duration;
  final bool isFrontFacing;
}

/// Android camera engine for the Observation Portal.
///
/// Uses `package:camera` (Camera2/CameraX) exclusively — it never touches the
/// Windows-only `infravision_camera` method channel, which is the cause of the
/// historical `MissingPluginException` on Android (§7).
class MobileCameraService extends ChangeNotifier {
  MobileCameraService._();
  static final MobileCameraService instance = MobileCameraService._();

  CameraController? _controller;
  List<CameraDescription> _cameras = const <CameraDescription>[];
  int _cameraIndex = 0;
  bool _initializing = false;
  bool _wantRunning = false;
  bool _capturing = false;
  bool _recording = false;
  DateTime? _recordingStartedAt;
  FlashMode _flashMode = FlashMode.auto;
  double _zoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  Offset? _focusPoint;
  Timer? _focusClearTimer;
  String? _lastError;
  CameraCapabilities _capabilities = CameraCapabilities.empty;
  DateTime? _lastInitAt;
  int _initCount = 0;

  // Getters -----------------------------------------------------------------
  CameraController? get controller => _controller;
  bool get isInitialized => _controller?.value.isInitialized ?? false;
  bool get isInitializing => _initializing;
  bool get isRunning => isInitialized;
  bool get isRecording => _recording;
  bool get isCapturing => _capturing;
  bool get isFrontFacing =>
      _cameras.isNotEmpty &&
      _cameraIndex < _cameras.length &&
      _cameras[_cameraIndex].lensDirection == CameraLensDirection.front;
  FlashMode get flashMode => _flashMode;
  double get zoom => _zoom;
  Offset? get focusPoint => _focusPoint;
  String? get lastError => _lastError;
  CameraCapabilities get capabilities => _capabilities;
  DateTime? get lastInitAt => _lastInitAt;
  int get initCount => _initCount;
  Duration? get recordingElapsed => _recordingStartedAt == null
      ? null
      : DateTime.now().difference(_recordingStartedAt!);
  /// Contextual camera permission request (§68) — never at app startup.
  Future<bool> ensurePermission() async {
    final PermissionStatus status = await Permission.camera.status;
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) {
      _lastError = 'Camera permission is blocked. Allow camera access in Android settings.';
      notifyListeners();
      return false;
    }
    final PermissionStatus requested = await Permission.camera.request();
    if (!requested.isGranted) {
      _lastError = 'Camera permission is required to capture evidence.';
      notifyListeners();
      return false;
    }
    return true;
  }

  /// Enumerates hardware cameras and derives the real capability set (§8/§9).
  Future<void> enumerateCameras() async {
    try {
      final List<CameraDescription> found = await availableCameras();
      _cameras = List<CameraDescription>.unmodifiable(found);
      if (_cameras.isEmpty) {
        _lastError = 'No camera hardware was reported by the device.';
      } else {
        _lastError = null;
      }
    } catch (e) {
      // Never surfaces a raw exception — only a user-safe message (§84).
      AppLog.e('Camera', 'Camera enumeration failed: $e');
      _cameras = const <CameraDescription>[];
      _lastError = 'Camera hardware is unavailable right now.';
    }
    notifyListeners();
  }

  Future<bool> initialize({
    CameraLensDirection preferred = CameraLensDirection.back,
    ResolutionPreset preset = ResolutionPreset.high,
  }) async {
    if (_initializing) return false;
    _wantRunning = true;
    _initializing = true;
    _lastError = null;
    notifyListeners();
    bool flashSupported = false;

    try {
      if (!await ensurePermission()) {
        _initializing = false;
        notifyListeners();
        return false;
      }
      if (_cameras.isEmpty) {
        await enumerateCameras();
      }
      if (_cameras.isEmpty) {
        _initializing = false;
        notifyListeners();
        return false;
      }

      int index = _cameras.indexWhere((CameraDescription c) => c.lensDirection == preferred);
      if (index < 0) index = _cameras.indexWhere((CameraDescription c) => c.lensDirection == CameraLensDirection.back);
      if (index < 0) index = 0;
      _cameraIndex = index;

      await _controller?.dispose();
      _controller = null;

      final CameraController controller = CameraController(
        _cameras[_cameraIndex],
        preset,
        // Evidence audio is intentionally not recorded: it keeps clips small,
        // avoids a microphone permission just to capture road defects.
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      _controller = controller;
      await controller.initialize();

      try {
        _minZoom = await controller.getMinZoomLevel();
        _maxZoom = await controller.getMaxZoomLevel();
        _zoom = _zoom.clamp(_minZoom, _maxZoom).toDouble();
        await controller.setFlashMode(_flashMode);
        flashSupported = true;
      } on CameraException {
        flashSupported = false;
        AppLog.d('Camera', 'Flash not supported on the active camera');
        _minZoom = 1;
        _maxZoom = 1;
      } catch (e) {
        AppLog.d('Camera', 'Zoom/flash probe unsupported on this device: $e');
        _minZoom = 1;
        _maxZoom = 1;
      }

      _capabilities = CameraCapabilities(
        cameras: _cameras,
        hasRear: _cameras
            .any((CameraDescription c) => c.lensDirection == CameraLensDirection.back),
        hasFront: _cameras
            .any((CameraDescription c) => c.lensDirection == CameraLensDirection.front),
        hasFlash: flashSupported,
        minZoom: _minZoom,
        maxZoom: _maxZoom,
        presets: _zoomPresets(_minZoom, _maxZoom),
      );

      _lastInitAt = DateTime.now();
      _initCount++;
      _initializing = false;
      _lastError = null;
      notifyListeners();
      return true;
    } on CameraException catch (e) {
      AppLog.e('Camera', 'Init failed: ${e.code} ${e.description}');
      _initializing = false;
      _lastError = _friendlyCameraError(e);
      await _disposeController();
      notifyListeners();
      return false;
    } catch (e) {
      AppLog.e('Camera', 'Unexpected camera failure: $e');
      _initializing = false;
      _lastError = 'Camera could not be started on this device.';
      await _disposeController();
      notifyListeners();
      return false;
    }
  }

  /// Only offers zoom steps the hardware reports (§9: 0.5x only if real).
  List<ZoomPreset> _zoomPresets(double min, double max) {
    const List<double> candidates = <double>[0.5, 0.6, 0.8, 1.0, 1.5, 2.0, 3.0, 4.0, 5.0, 8.0, 10.0];
    final List<ZoomPreset> presets = <ZoomPreset>[];
    for (final double factor in candidates) {
      if (factor < min || factor > max) continue;
      final String label = factor < 1
          ? '${factor.toStringAsFixed(1)}x'
          : '${factor == factor.roundToDouble() ? factor.toInt() : factor}x';
      presets.add(ZoomPreset(factor, label));
    }
    if (presets.isEmpty) presets.add(const ZoomPreset(1, '1x'));
    return presets;
  }

  String _friendlyCameraError(CameraException error) {
    switch (error.code) {
      case 'CameraAccessDenied':
      case 'cameraAccessDenied':
        return 'Camera permission was denied.';
      case 'VideoCameraAccessDenied':
        return 'Video capture permission was denied.';
      case 'CameraAccessDeniedWithoutPrompt':
      case 'CameraAccessRestricted':
        return 'Camera access is restricted on this device.';
      default:
        return 'Camera is unavailable right now. Try again or free up memory.';
    }
  }
  /// Switches between rear and front (§10). The rear camera stays default.
  Future<bool> switchCamera() async {
    if (_cameras.length < 2) return false;
    final CameraLensDirection target =
        isFrontFacing ? CameraLensDirection.back : CameraLensDirection.front;
    return initialize(
      preferred: target,
      preset: ResolutionPreset.high,
    );
  }

  Future<void> selectLens(CameraDescription description) async {
    final int index = _cameras.indexWhere((CameraDescription c) => c.name == description.name);
    if (index < 0 || index == _cameraIndex) return;
    _cameraIndex = index;
    await initialize(
      preferred: description.lensDirection,
      preset: ResolutionPreset.high,
    );
  }

  Future<void> setZoom(double level) async {
    final CameraController? current = _controller;
    if (current == null || !current.value.isInitialized) return;
    final double target = level.clamp(_minZoom, _maxZoom).toDouble();
    try {
      await current.setZoomLevel(target);
      _zoom = target;
      notifyListeners();
    } catch (e) {
      AppLog.d('Camera', 'setZoom rejected: $e');
    }
  }

  /// Cycles auto -> on -> off (front camera has no flash: disabled in UI).
  Future<void> cycleFlash() async {
    if (!_capabilities.hasFlash || isFrontFacing) return;
    final FlashMode next = switch (_flashMode) {
      FlashMode.auto => FlashMode.always,
      FlashMode.always => FlashMode.off,
      _ => FlashMode.auto,
    };
    await setFlash(next);
  }

  Future<void> setFlash(FlashMode mode) async {
    final CameraController? current = _controller;
    _flashMode = mode;
    notifyListeners();
    if (current == null || !current.value.isInitialized) return;
    try {
      await current.setFlashMode(mode);
    } catch (e) {
      AppLog.d('Camera', 'setFlashMode rejected: $e');
    }
  }

  /// Tap-to-focus with a temporary visual marker (§11).
  Future<void> focusAt(Offset normalized) async {
    final CameraController? current = _controller;
    if (current == null || !current.value.isInitialized) return;
    try {
      await current.setFocusPoint(normalized);
      await current.setExposurePoint(normalized);
      _focusPoint = normalized;
      notifyListeners();
      _focusClearTimer?.cancel();
      _focusClearTimer = Timer(const Duration(seconds: 2), () {
        _focusPoint = null;
        notifyListeners();
      });
    } catch (e) {
      AppLog.d('Camera', 'focusAt rejected: $e');
    }
  }
  /// Captures a still image. A guard flag makes double-taps impossible (§33).
  Future<CameraCapture?> capturePhoto() async {
    final CameraController? current = _controller;
    if (current == null || !current.value.isInitialized) {
      _lastError = 'Camera is not running.';
      notifyListeners();
      return null;
    }
    if (_capturing || _recording) return null;

    _capturing = true;
    notifyListeners();
    try {
      final XFile file = await current.takePicture();
      final CameraCapture capture = CameraCapture(
        file: File(file.path),
        capturedAt: DateTime.now(),
        isFrontFacing: isFrontFacing,
        zoomFactor: _zoom,
      );
      _capturing = false;
      notifyListeners();
      return capture;
    } on CameraException catch (e) {
      AppLog.e('Camera', 'takePicture failed: ${e.code}');
      _capturing = false;
      _lastError = 'Photo capture failed. Try again.';
      notifyListeners();
      return null;
    } catch (e) {
      AppLog.e('Camera', 'takePicture unexpected failure: $e');
      _capturing = false;
      _lastError = 'Photo capture failed. Try again.';
      notifyListeners();
      return null;
    }
  }

  Future<bool> startVideo() async {
    final CameraController? current = _controller;
    if (current == null || !current.value.isInitialized || _capturing) return false;
    if (_recording) return true;
    try {
      await current.startVideoRecording();
      _recording = true;
      _recordingStartedAt = DateTime.now();
      notifyListeners();
      return true;
    } catch (e) {
      AppLog.e('Camera', 'startVideoRecording failed: $e');
      _lastError = 'Video recording could not start on this device.';
      notifyListeners();
      return false;
    }
  }

  Future<CameraVideoCapture?> stopVideo() async {
    final CameraController? current = _controller;
    if (!_recording || current == null) return null;
    try {
      final XFile file = await current.stopVideoRecording();
      final DateTime started = _recordingStartedAt ?? DateTime.now();
      _recording = false;
      _recordingStartedAt = null;
      notifyListeners();
      return CameraVideoCapture(
        file: File(file.path),
        capturedAt: started,
        duration: DateTime.now().difference(started),
        isFrontFacing: isFrontFacing,
      );
    } catch (e) {
      AppLog.e('Camera', 'stopVideoRecording failed: $e');
      _recording = false;
      _recordingStartedAt = null;
      _lastError = 'Video recording could not be saved.';
      notifyListeners();
      return null;
    }
  }

  /// OS lifecycle handling (§12): the camera is fully released while the app
  /// is backgrounded and re-created when it returns to the foreground.
  Future<void> handleLifecycle(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_wantRunning && !isInitialized && !_initializing) {
          await initialize(
            preferred: isFrontFacing
                ? CameraLensDirection.front
                : CameraLensDirection.back,
          );
        }
        break;
      case AppLifecycleState.inactive:
        // Screen-off / interruption: stop recording but keep the session.
        if (_recording) {
          await stopVideo();
        }
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _wantRunning = isInitialized;
        await _disposeController();
        break;
    }
  }

  Future<void> _disposeController() async {
    _focusClearTimer?.cancel();
    _focusClearTimer = null;
    final CameraController? current = _controller;
    _controller = null;
    _recording = false;
    _recordingStartedAt = null;
    if (current != null) {
      try {
        await current.dispose();
      } catch (e) {
        AppLog.d('Camera', 'dispose ignored error: $e');
      }
    }
    notifyListeners();
  }

  /// Explicit release (screen exit / battery saving §57).
  Future<void> stop() async {
    _wantRunning = false;
    await _disposeController();
  }

  @override
  void dispose() {
    _focusClearTimer?.cancel();
    unawaited(_disposeController());
    super.dispose();
  }
}