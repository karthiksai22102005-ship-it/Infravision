import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:infravision_camera/infravision_camera.dart';

import 'frame_controller.dart';

/// Manages the Windows webcam lifecycle with reactive state notifications.
class CameraService extends ChangeNotifier {
  CameraService._();

  static final CameraService instance = CameraService._();

  final FrameController frameController = FrameController.instance;

  List<CameraDevice> _devices = const [];
  CameraDevice? _selectedDevice;
  String? _selectedResolution;
  CameraStartResult? _startResult;
  CameraState _state = CameraState.stopped;
  String? _lastError;

  /// Available camera devices.
  List<CameraDevice> get devices => _devices;

  /// Currently selected camera device.
  CameraDevice? get selectedDevice => _selectedDevice;

  /// Current camera state.
  CameraState get state => _state;

  /// Whether the camera is currently running.
  bool get isRunning => _state == CameraState.running;

  /// Whether the camera is starting.
  bool get isStarting => _state == CameraState.starting;

  /// Whether the camera is shutting down and native resources are releasing.
  bool get isStopping => _state == CameraState.stopping;

  /// Whether the camera is in an error state.
  bool get hasError => _state == CameraState.error;

  /// Last error message (if any).
  String? get lastError => _lastError;

  /// Texture ID for the live preview (null when not running).
  int? get textureId => _startResult?.textureId;

  /// Capture resolution width.
  int? get width => _startResult?.width;

  /// Capture resolution height.
  int? get height => _startResult?.height;

  /// Negotiated camera FPS.
  int? get cameraFps => _startResult?.fps;

  /// Pixel format of the native frame buffer.
  String? get pixelFormat => _startResult?.pixelFormat;

  /// Measured actual FPS from [FrameController].
  double get measuredFps => frameController.currentFps;

  /// Total frames received.
  int get framesReceived => frameController.totalFrames;

  /// Enumerate available camera devices.
  Future<List<CameraDevice>> enumerateCameras() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) {
      _devices = const [];
      notifyListeners();
      return _devices;
    }
    try {
      _devices = await InfravisionCamera.availableCameras();
      _lastError = null;
      if (_devices.isNotEmpty && _selectedDevice == null) {
        _selectedDevice = _devices.first;
      }
    } catch (e) {
      _lastError = 'Failed to enumerate cameras: $e\nCheck Windows Privacy & Security -> Camera settings.';
      debugPrint(_lastError!);
      _devices = const [];
    }
    notifyListeners();
    return _devices;
  }

  /// Select a camera device by index.
  void selectDevice(int index) {
    if (index >= 0 && index < _devices.length) {
      if (_selectedDevice?.id != _devices[index].id) {
        _selectedDevice = _devices[index];
        _selectedResolution = null; // Reset resolution when device changes
        notifyListeners();
      }
    }
  }

  /// Current selected resolution (e.g. "1280x720").
  String? get selectedResolution => _selectedResolution;

  /// Set the selected resolution.
  void selectResolution(String? resolution) {
    if (_selectedResolution != resolution) {
      _selectedResolution = resolution;
      notifyListeners();
      if (isRunning) {
        restartCamera();
      }
    }
  }

  /// Start the selected camera (or the first available one).
  Future<bool> startCamera() async {
    if (_state == CameraState.running || _state == CameraState.starting) {
      return true;
    }
    if (_state == CameraState.stopping) return false;

    if (_devices.isEmpty) {
      await enumerateCameras();
    }

    if (_devices.isEmpty) {
      _lastError = 'No camera devices found. Ensure webcam is connected and app has camera permissions.';
      _state = CameraState.error;
      notifyListeners();
      return false;
    }

    _selectedDevice ??= _devices.first;

    _state = CameraState.starting;
    _lastError = null;
    notifyListeners();

    try {
      frameController.start();

      int? reqWidth;
      int? reqHeight;
      if (_selectedResolution != null) {
        final parts = _selectedResolution!.split('x');
        if (parts.length == 2) {
          reqWidth = int.tryParse(parts[0]);
          reqHeight = int.tryParse(parts[1]);
        }
      }

      _startResult = await InfravisionCamera.startCamera(
        _selectedDevice!.id,
        width: reqWidth,
        height: reqHeight,
      );
      _state = CameraState.running;
      _lastError = null;
      notifyListeners();

      debugPrint(
        'Camera started: ${_selectedDevice!.name} '
        '${_startResult!.width}x${_startResult!.height} @ ${_startResult!.fps} fps '
        'textureId=${_startResult!.textureId} format=${_startResult!.pixelFormat}',
      );
      return true;
    } catch (e) {
      _lastError = 'Failed to start camera: $e';
      debugPrint(_lastError!);
      frameController.stop();
      _state = CameraState.error;
      _startResult = null;
      notifyListeners();
      return false;
    }
  }

  /// Stop the camera and release resources.
  Future<void> stopCamera() async {
    if (_state == CameraState.stopped) return;

    _state = CameraState.stopping;
    notifyListeners();
    frameController.stop();

    try {
      await InfravisionCamera.stopCamera();
    } catch (e) {
      debugPrint('Error stopping camera: $e');
    }

    _startResult = null;
    _state = CameraState.stopped;
    notifyListeners();
  }

  /// Restart the camera.
  Future<bool> restartCamera() async {
    await stopCamera();
    return startCamera();
  }

  @override
  void dispose() {
    stopCamera();
    frameController.dispose();
    super.dispose();
  }
}