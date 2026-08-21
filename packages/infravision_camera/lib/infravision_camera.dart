import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Camera lifecycle states.
enum CameraState {
  stopped,
  starting,
  running,
  stopping,
  error,
}

/// A single camera device description.
class CameraDevice {
  const CameraDevice({
    required this.id,
    required this.name,
    this.resolutions = const [],
  });

  final String id;
  final String name;
  final List<String> resolutions;

  @override
  String toString() => 'CameraDevice(id: $id, name: $name, resolutions: $resolutions)';
}

/// A single video frame captured from the webcam.
class CameraFrame {
  const CameraFrame({
    required this.bytes,
    required this.width,
    required this.height,
    required this.timestamp,
    required this.pixelFormat,
  });

  /// Raw BGRA pixel data.
  final Uint8List bytes;

  final int width;
  final int height;

  /// Monotonic timestamp in microseconds.
  final int timestamp;

  /// Native byte layout. The Windows implementation delivers BGRA32.
  final String pixelFormat;

  int get length => bytes.length;
}

/// Result of starting the camera.
class CameraStartResult {
  const CameraStartResult({
    required this.textureId,
    required this.width,
    required this.height,
    required this.fps,
    required this.pixelFormat,
  });

  final int textureId;
  final int width;
  final int height;
  final int fps;
  final String pixelFormat;
}

/// The InfraVision Windows webcam plugin.
///
/// Uses Media Foundation on Windows to capture real webcam frames.
/// Frames are exposed both as a Flutter texture (for live preview) and
/// as raw bytes via [frames] stream (for future inference).
class InfravisionCamera {
  InfravisionCamera._();

  static const MethodChannel _channel = MethodChannel('infravision_camera');
  static const MethodChannel _frameChannel =
      MethodChannel('infravision_camera/frames');

  static final StreamController<CameraFrame> _frameController =
      StreamController<CameraFrame>.broadcast();

  static bool _initialized = false;
  static bool _isRunning = false;

  /// Stream of real camera frames (raw bytes).
  static Stream<CameraFrame> get frames => _frameController.stream;

  /// Whether the camera is currently running.
  static bool get isRunning => _isRunning;

  /// Initialize the plugin (call once at app startup).
  static void initialize() {
    if (_initialized) return;
    _initialized = true;
    _frameChannel.setMethodCallHandler(_onFrameCall);
  }

  /// Enumerate available camera devices.
  static Future<List<CameraDevice>> availableCameras() async {
    final List<dynamic> result =
        await _channel.invokeMethod('availableCameras');
    return result
        .map((e) => CameraDevice(
              id: e['id'] as String,
              name: e['name'] as String,
              resolutions: (e['resolutions'] as List<dynamic>?)
                      ?.map((r) => r as String)
                      .toList() ??
                  const [],
            ))
        .toList();
  }

  /// Start the camera with the given device id and optional resolution.
  ///
  /// Returns a [CameraStartResult] with the texture id and capture info.
  static Future<CameraStartResult> startCamera(String deviceId, {int? width, int? height}) async {
    final Map<dynamic, dynamic> result = await _channel.invokeMethod(
      'startCamera',
      {
        'deviceId': deviceId,
        'width': width,
        'height': height,
      },
    );
    final startResult = CameraStartResult(
      textureId: result['textureId'] as int,
      width: result['width'] as int,
      height: result['height'] as int,
      fps: result['fps'] as int,
      pixelFormat: result['pixelFormat'] as String? ?? 'BGRA32',
    );
    _isRunning = true;
    return startResult;
  }

  /// Stop the camera and release resources.
  static Future<void> stopCamera() async {
    try {
      await _channel.invokeMethod('stopCamera');
    } finally {
      _isRunning = false;
    }
  }

  /// Internal: called by the native side to push a frame via method channel.
  static Future<dynamic> _onFrameCall(MethodCall call) async {
    if (call.method != 'onFrame') return null;
    final event = call.arguments;
    if (event is! Map) return null;
    final bytes = event['bytes'];
    Uint8List uint8Bytes;
    if (bytes is Uint8List) {
      uint8Bytes = bytes;
    } else if (bytes is List<int>) {
      uint8Bytes = Uint8List.fromList(bytes);
    } else {
      debugPrint('Frame rejected: bytes is ${bytes.runtimeType}, not Uint8List or List<int>');
      return null;
    }
    final width = event['width'];
    final height = event['height'];
    final timestamp = event['timestamp'];
    if (width is! int || height is! int || timestamp is! int) {
      debugPrint('Frame rejected: invalid dimensions or timestamp');
      return null;
    }
    if (width <= 0 || height <= 0 || uint8Bytes.length < width * height * 4) {
      debugPrint('Frame rejected: invalid size ${uint8Bytes.length} for ${width}x$height');
      return null;
    }
    if (_frameController.isClosed) return null;
    _frameController.add(CameraFrame(
      bytes: uint8Bytes,
      width: width,
      height: height,
      timestamp: timestamp,
      pixelFormat: event['pixelFormat'] as String? ?? 'BGRA32',
    ));
    return null;
  }

  /// Dispose resources.
  static Future<void> dispose() async {
    await stopCamera();
    if (!_frameController.isClosed) {
      await _frameController.close();
    }
  }
}
