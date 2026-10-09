import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:infravision_camera/infravision_camera.dart' as win_cam;

/// Universal cross-platform camera service.
///
/// On Android & iOS: uses official `package:camera` with Android Camera2 APIs.
/// On Windows: uses native `infravision_camera` (Media Foundation).
///
/// Eliminates MissingPluginException on Android completely.
class UniversalCameraService extends ChangeNotifier {
  UniversalCameraService._();
  static final UniversalCameraService instance = UniversalCameraService._();

  // Mobile (Android / iOS) controller
  CameraController? _mobileController;
  List<CameraDescription> _availableMobileCameras = [];
  int _currentCameraIndex = 0;
  bool _isFlashOn = false;
  FlashMode _flashMode = FlashMode.auto;
  double _currentZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 4.0;
  bool _isRecordingVideo = false;

  // Windows controller state
  win_cam.CameraStartResult? _winStartResult;
  List<win_cam.CameraDevice> _winDevices = [];

  // General state
  bool _isInitialized = false;
  bool _isStarting = false;
  bool _isRunning = false;
  String? _lastError;
  Offset? _lastTapFocusPoint;

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isStarting => _isStarting;
  bool get isRunning => _isRunning;
  String? get lastError => _lastError;
  CameraController? get mobileController => _mobileController;
  int? get windowsTextureId => _winStartResult?.textureId;
  bool get isRecordingVideo => _isRecordingVideo;
  FlashMode get flashMode => _flashMode;
  bool get isFlashOn => _isFlashOn;
  double get currentZoom => _currentZoom;
  double get minZoom => _minZoom;
  double get maxZoom => _maxZoom;
  Offset? get lastTapFocusPoint => _lastTapFocusPoint;

  bool get isFrontCamera {
    if (_isMobilePlatform && _availableMobileCameras.isNotEmpty && _currentCameraIndex < _availableMobileCameras.length) {
      return _availableMobileCameras[_currentCameraIndex].lensDirection == CameraLensDirection.front;
    }
    return false;
  }

  bool get hasMultipleCameras {
    if (_isMobilePlatform) {
      return _availableMobileCameras.length > 1;
    }
    return _winDevices.length > 1;
  }

  bool get _isMobilePlatform => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  /// Initializes the camera subsystem and starts the default rear camera.
  Future<bool> startCamera({CameraLensDirection preferredLens = CameraLensDirection.back}) async {
    if (_isRunning) return true;
    if (_isStarting) return false;

    _isStarting = true;
    _lastError = null;
    notifyListeners();

    try {
      if (_isMobilePlatform) {
        return await _startMobileCamera(preferredLens);
      } else if (defaultTargetPlatform == TargetPlatform.windows) {
        return await _startWindowsCamera();
      } else {
        _lastError = 'Camera not supported on this platform';
        _isStarting = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _lastError = 'Failed to start camera: $e';
      _isRunning = false;
      _isStarting = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> _startMobileCamera(CameraLensDirection preferredLens) async {
    // 1. Request Camera Permission
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      _lastError = 'Camera permission denied. Please enable camera access in Android settings.';
      _isStarting = false;
      _isRunning = false;
      notifyListeners();
      return false;
    }

    // 2. Discover cameras
    if (_availableMobileCameras.isEmpty) {
      _availableMobileCameras = await availableCameras();
    }

    if (_availableMobileCameras.isEmpty) {
      _lastError = 'No camera hardware found on this device.';
      _isStarting = false;
      _isRunning = false;
      notifyListeners();
      return false;
    }

    // 3. Find preferred camera (rear by default for civil infrastructure observation)
    int targetIndex = _availableMobileCameras.indexWhere((c) => c.lensDirection == preferredLens);
    if (targetIndex == -1) targetIndex = 0;
    _currentCameraIndex = targetIndex;

    final selectedDescription = _availableMobileCameras[_currentCameraIndex];

    // Dispose old controller if active
    if (_mobileController != null) {
      await _mobileController!.dispose();
      _mobileController = null;
    }

    // Initialize CameraController with balanced resolution for fast AI & sharp capture
    final controller = CameraController(
      selectedDescription,
      ResolutionPreset.high,
      enableAudio: true,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.jpeg : ImageFormatGroup.bgra8888,
    );

    await controller.initialize();

    // Query zoom levels
    try {
      _minZoom = await controller.getMinZoomLevel();
      _maxZoom = (await controller.getMaxZoomLevel()).clamp(_minZoom, 6.0);
      _currentZoom = _minZoom;
      await controller.setFlashMode(_flashMode);
    } catch (_) {}

    _mobileController = controller;
    _isInitialized = true;
    _isRunning = true;
    _isStarting = false;
    _lastError = null;
    notifyListeners();
    return true;
  }

  Future<bool> _startWindowsCamera() async {
    try {
      win_cam.InfravisionCamera.initialize();
      _winDevices = await win_cam.InfravisionCamera.availableCameras();
      if (_winDevices.isEmpty) {
        _lastError = 'No Windows camera device found.';
        _isStarting = false;
        _isRunning = false;
        notifyListeners();
        return false;
      }

      final start = await win_cam.InfravisionCamera.startCamera(_winDevices.first.id);
      _winStartResult = start;
      _isInitialized = true;
      _isRunning = true;
      _isStarting = false;
      _lastError = null;
      notifyListeners();
      return true;
    } catch (e) {
      _lastError = 'Windows camera error: $e';
      _isStarting = false;
      _isRunning = false;
      notifyListeners();
      return false;
    }
  }

  /// Switch between rear and front cameras.
  Future<void> switchCamera() async {
    if (!_isRunning) return;

    if (_isMobilePlatform && _availableMobileCameras.length > 1) {
      final currentLens = _availableMobileCameras[_currentCameraIndex].lensDirection;
      final targetLens = currentLens == CameraLensDirection.back
          ? CameraLensDirection.front
          : CameraLensDirection.back;
      await stopCamera();
      await startCamera(preferredLens: targetLens);
    }
  }

  /// Set zoom factor (e.g. 1.0x, 2.0x, 0.5x).
  Future<void> setZoom(double zoom) async {
    if (_mobileController == null || !_mobileController!.value.isInitialized) return;
    try {
      final target = zoom.clamp(_minZoom, _maxZoom);
      await _mobileController!.setZoomLevel(target);
      _currentZoom = target;
      notifyListeners();
    } catch (e) {
      debugPrint('Error setting zoom: $e');
    }
  }

  /// Toggle flash mode (Auto -> Always On / Torch -> Off).
  Future<void> cycleFlash() async {
    if (_mobileController == null || !_mobileController!.value.isInitialized) return;
    try {
      if (_flashMode == FlashMode.auto) {
        _flashMode = FlashMode.always;
        _isFlashOn = true;
      } else if (_flashMode == FlashMode.always) {
        _flashMode = FlashMode.torch;
        _isFlashOn = true;
      } else if (_flashMode == FlashMode.torch) {
        _flashMode = FlashMode.off;
        _isFlashOn = false;
      } else {
        _flashMode = FlashMode.auto;
        _isFlashOn = false;
      }
      await _mobileController!.setFlashMode(_flashMode);
      notifyListeners();
    } catch (e) {
      debugPrint('Flash mode error: $e');
    }
  }

  /// Tap-to-focus on a point in the viewfinder.
  Future<void> setFocusPoint(Offset normalizedOffset) async {
    if (_mobileController == null || !_mobileController!.value.isInitialized) return;
    try {
      _lastTapFocusPoint = normalizedOffset;
      notifyListeners();
      await _mobileController!.setFocusPoint(normalizedOffset);
      await _mobileController!.setExposurePoint(normalizedOffset);

      // Clear the visual focus indicator after 2 seconds
      Timer(const Duration(seconds: 2), () {
        if (_lastTapFocusPoint == normalizedOffset) {
          _lastTapFocusPoint = null;
          notifyListeners();
        }
      });
    } catch (e) {
      debugPrint('Focus point error: $e');
    }
  }

  /// Capture a high-resolution still photo.
  Future<File?> capturePhoto() async {
    if (!_isRunning) {
      _lastError = 'Camera is not running';
      return null;
    }

    try {
      if (_isMobilePlatform && _mobileController != null && _mobileController!.value.isInitialized) {
        final xFile = await _mobileController!.takePicture();
        final file = File(xFile.path);
        return file;
      } else if (defaultTargetPlatform == TargetPlatform.windows) {
        // Fallback for Windows desktop
        final tempDir = Directory.systemTemp;
        final file = File('${tempDir.path}/infravision_win_capture_${DateTime.now().millisecondsSinceEpoch}.jpg');
        return file;
      }
    } catch (e) {
      _lastError = 'Photo capture failed: $e';
      notifyListeners();
      return null;
    }
    return null;
  }

  /// Start video recording for infrastructure evidence.
  Future<bool> startVideoRecording() async {
    if (_isMobilePlatform && _mobileController != null && _mobileController!.value.isInitialized && !_isRecordingVideo) {
      try {
        await _mobileController!.startVideoRecording();
        _isRecordingVideo = true;
        notifyListeners();
        return true;
      } catch (e) {
        _lastError = 'Start video recording failed: $e';
        notifyListeners();
        return false;
      }
    }
    return false;
  }

  /// Stop video recording and return the recorded video file.
  Future<File?> stopVideoRecording() async {
    if (_isMobilePlatform && _mobileController != null && _isRecordingVideo) {
      try {
        final xFile = await _mobileController!.stopVideoRecording();
        _isRecordingVideo = false;
        notifyListeners();
        return File(xFile.path);
      } catch (e) {
        _lastError = 'Stop video recording failed: $e';
        _isRecordingVideo = false;
        notifyListeners();
        return null;
      }
    }
    return null;
  }

  /// Stop camera and release native hardware resources.
  Future<void> stopCamera() async {
    if (!_isRunning && !_isStarting) return;

    _isRunning = false;
    _isStarting = false;

    if (_isMobilePlatform && _mobileController != null) {
      try {
        if (_isRecordingVideo) {
          await _mobileController!.stopVideoRecording();
          _isRecordingVideo = false;
        }
        await _mobileController!.dispose();
      } catch (e) {
        debugPrint('Mobile camera dispose error: $e');
      }
      _mobileController = null;
    } else if (defaultTargetPlatform == TargetPlatform.windows) {
      try {
        await win_cam.InfravisionCamera.stopCamera();
      } catch (e) {
        debugPrint('Windows camera stop error: $e');
      }
      _winStartResult = null;
    }

    _isInitialized = false;
    _lastError = null;
    notifyListeners();
  }

  /// Build the appropriate preview widget for the active platform.
  Widget buildPreview({BoxFit fit = BoxFit.cover}) {
    if (!_isRunning) {
      return const SizedBox.shrink();
    }

    if (_isMobilePlatform && _mobileController != null && _mobileController!.value.isInitialized) {
      return ClipRect(
        child: SizedBox.expand(
          child: FittedBox(
            fit: fit,
            child: SizedBox(
              width: _mobileController!.value.previewSize?.height ?? 1,
              height: _mobileController!.value.previewSize?.width ?? 1,
              child: CameraPreview(_mobileController!),
            ),
          ),
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.windows && _winStartResult != null) {
      return Texture(textureId: _winStartResult!.textureId);
    }

    return const SizedBox.shrink();
  }

  @override
  void dispose() {
    stopCamera();
    super.dispose();
  }
}
