import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import 'package:infravision_camera/infravision_camera.dart';

/// A single processed frame with timing metadata.
class ProcessedFrame {
  const ProcessedFrame({
    required this.frame,
    required this.receivedAt,
  });

  final CameraFrame frame;

  /// Monotonic timestamp (microseconds) when the frame was received in Dart.
  final int receivedAt;
}

/// FrameController receives real camera frames from the native plugin,
/// measures actual FPS, and exposes the stream to the UI and future
/// vision engine.
///
/// This is the single source of truth for frame flow in the app.
class FrameController {
  FrameController._();

  static final FrameController instance = FrameController._();

  final StreamController<ProcessedFrame> _frames =
      StreamController<ProcessedFrame>.broadcast();

  // FPS measurement state.
  int _frameCount = 0;
  int _fpsWindowStartUs = 0;
  double _currentFps = 0.0;
  StreamSubscription<CameraFrame>? _subscription;

  /// Total number of frames received since the camera started.
  int _totalFrames = 0;

  /// Stream of real camera frames with timing metadata.
  Stream<ProcessedFrame> get frames => _frames.stream;

  /// Current measured camera FPS (frames per second).
  double get currentFps => _currentFps;

  /// Total frames received since start.
  int get totalFrames => _totalFrames;

  /// Whether frames are flowing.
  bool get isActive => _subscription != null;

  /// Start listening to the native camera frame stream.
  void start() {
    if (_subscription != null) return;
    _frameCount = 0;
    _fpsWindowStartUs = 0;
    _currentFps = 0.0;
    _totalFrames = 0;

    _subscription = InfravisionCamera.frames.listen(
      _onFrame,
      onError: (Object e) {
        debugPrint('FrameController error: $e');
      },
    );
  }

  /// Stop listening to the native camera frame stream.
  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _frameCount = 0;
    _fpsWindowStartUs = 0;
    _currentFps = 0.0;
    _totalFrames = 0;
  }

  void _onFrame(CameraFrame frame) {
    final now = DateTime.now().microsecondsSinceEpoch;

    _totalFrames++;

    // Measure FPS over a 1-second sliding window.
    if (_fpsWindowStartUs == 0) {
      _fpsWindowStartUs = now;
      _frameCount = 1;
    } else {
      _frameCount++;
      final elapsedUs = now - _fpsWindowStartUs;
      if (elapsedUs >= AppConfig.fpsMeasurementWindowUs) {
        _currentFps = _frameCount * 1000000.0 / elapsedUs;
        _frameCount = 0;
        _fpsWindowStartUs = now;
      }
    }

    if (!_frames.isClosed) {
      _frames.add(ProcessedFrame(frame: frame, receivedAt: now));
    }
  }

  /// Dispose resources.
  void dispose() {
    stop();
    if (!_frames.isClosed) {
      _frames.close();
    }
  }
}
