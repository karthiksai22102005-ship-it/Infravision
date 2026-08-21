import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:infravision_camera/infravision_camera.dart';

import '../camera/frame_controller.dart';
import '../models/detection_history_entry.dart';
import '../performance/telemetry_service.dart';
import '../tracking/multi_object_tracker.dart';
import 'ensemble/ensemble_engine.dart';
import 'ensemble/unified_detection.dart';
import 'models/feature_model_b.dart';
import 'models/infrastructure_model_c.dart';
import 'models/vision_model.dart';
import 'models/yolo_model_a.dart';

/// Configurable performance modes for multi-model inference.
enum InferenceMode {
  fast,
  balanced,
  quality,
}

/// Comprehensive multi-model telemetry results for a single inference cycle.
class MultiModelVisionResult {
  const MultiModelVisionResult({
    required this.unifiedDetections,
    required this.trackedObjects,
    required this.rawModelDetections,
    required this.modelALatencyMs,
    required this.modelBLatencyMs,
    required this.modelCLatencyMs,
    required this.ensembleLatencyMs,
    required this.trackingLatencyMs,
    required this.totalLatencyMs,
    required this.inferenceFps,
    required this.frameTimestamp,
    required this.frameWidth,
    required this.frameHeight,
  });

  final List<UnifiedDetection> unifiedDetections;
  final List<MultiTrackObject> trackedObjects;
  final Map<String, List<RawModelDetection>> rawModelDetections;
  final double modelALatencyMs;
  final double modelBLatencyMs;
  final double modelCLatencyMs;
  final double ensembleLatencyMs;
  final double trackingLatencyMs;
  final double totalLatencyMs;
  final double inferenceFps;
  final int frameTimestamp;
  final int frameWidth;
  final int frameHeight;
}

/// Central VisionService orchestrating Level-2 multi-model execution,
/// normalization, ensemble fusion, and multi-object tracking.
class VisionService extends ChangeNotifier {
  VisionService._() {
    _modelA = YoloModelA();
    _modelB = FeatureModelB();
    _modelC = InfrastructureModelC();
  }

  static final VisionService instance = VisionService._();

  late final YoloModelA _modelA;
  late final FeatureModelB _modelB;
  late final InfrastructureModelC _modelC;

  final EnsembleEngine _ensembleEngine = EnsembleEngine();
  final MultiObjectTracker _tracker = MultiObjectTracker();

  StreamSubscription<ProcessedFrame>? _frameSubscription;
  bool _isProcessing = false;
  int _lastInferenceUs = 0;

  CameraFrame? _latestRawFrame;

  // Inference FPS counter
  int _inferenceCount = 0;
  int _fpsWindowStartUs = 0;
  double _measuredInferenceFps = 0.0;

  // Settings
  bool _aiEnabled = true;
  bool _overlayEnabled = false; // Default OFF as required
  bool _trackingEnabled = true;
  double _confidenceThreshold = 0.45;
  int _targetInferenceFps = 8;
  final bool _showSaliency = false;
  InferenceMode _inferenceMode = InferenceMode.balanced;

  // Session detection history
  final List<DetectionHistoryEntry> _sessionHistory = [];
  MultiModelVisionResult? _latestResult;

  // Model references
  YoloModelA get modelA => _modelA;
  FeatureModelB get modelB => _modelB;
  InfrastructureModelC get modelC => _modelC;

  EnsembleEngine get ensembleEngine => _ensembleEngine;
  MultiObjectTracker get tracker => _tracker;

  MultiModelVisionResult? get latestResult => _latestResult;
  List<MultiTrackObject> get trackedObjects =>
      _latestResult?.trackedObjects ?? const [];
  List<UnifiedDetection> get unifiedDetections =>
      _latestResult?.unifiedDetections ?? const [];
  List<DetectionHistoryEntry> get sessionHistory =>
      List.unmodifiable(_sessionHistory);

  double get inferenceFps => _measuredInferenceFps;
  double get latencyMs => _latestResult?.totalLatencyMs ?? 0.0;
  bool get aiEnabled => _aiEnabled;
  bool get overlayEnabled => _overlayEnabled;
  bool get trackingEnabled => _trackingEnabled;
  double get confidenceThreshold => _confidenceThreshold;
  int get targetInferenceFps => _targetInferenceFps;
  bool get showSaliency => _showSaliency;
  InferenceMode get inferenceMode => _inferenceMode;

  /// Start the multi-model vision pipeline and load all models.
  Future<void> start() async {
    if (_frameSubscription != null) return;
    _tracker.reset();

    // Load models
    await Future.wait([
      _modelA.load(),
      _modelB.load(),
      _modelC.load(),
    ]);

    notifyListeners();

    _frameSubscription = FrameController.instance.frames.listen(
      _processFrame,
      onError: (Object err) {
        debugPrint('VisionService frame error: $err');
      },
    );
  }

  /// Stop the vision pipeline.
  void stop() {
    _frameSubscription?.cancel();
    _frameSubscription = null;
    _tracker.reset();
    _latestResult = null;
    _isProcessing = false;
    notifyListeners();
  }

  void setAiEnabled(bool enabled) {
    if (_aiEnabled != enabled) {
      _aiEnabled = enabled;
      if (!enabled) _latestResult = null;
      notifyListeners();
    }
  }

  void setOverlayEnabled(bool enabled) {
    if (_overlayEnabled != enabled) {
      _overlayEnabled = enabled;
      notifyListeners();
    }
  }

  void setTrackingEnabled(bool enabled) {
    if (_trackingEnabled != enabled) {
      _trackingEnabled = enabled;
      if (!enabled) _tracker.reset();
      notifyListeners();
    }
  }

  void setConfidenceThreshold(double threshold) {
    if (_confidenceThreshold != threshold) {
      _confidenceThreshold = threshold;
      notifyListeners();
    }
  }

  void setTargetInferenceFps(int fps) {
    if (_targetInferenceFps != fps) {
      _targetInferenceFps = fps;
      notifyListeners();
    }
  }

  void setInferenceMode(InferenceMode mode) {
    if (_inferenceMode != mode) {
      _inferenceMode = mode;
      switch (mode) {
        case InferenceMode.fast:
          _targetInferenceFps = 12;
          _modelA.updateMetadata(_modelA.metadata.copyWith(enabled: true));
          _modelB.updateMetadata(_modelB.metadata.copyWith(enabled: false));
          _modelC.updateMetadata(_modelC.metadata.copyWith(enabled: false));
          break;
        case InferenceMode.balanced:
          _targetInferenceFps = 8;
          _modelA.updateMetadata(_modelA.metadata.copyWith(enabled: true));
          _modelB.updateMetadata(_modelB.metadata.copyWith(enabled: true));
          _modelC.updateMetadata(_modelC.metadata.copyWith(enabled: false));
          break;
        case InferenceMode.quality:
          _targetInferenceFps = 5;
          _modelA.updateMetadata(_modelA.metadata.copyWith(enabled: true));
          _modelB.updateMetadata(_modelB.metadata.copyWith(enabled: true));
          _modelC.updateMetadata(_modelC.metadata.copyWith(enabled: true));
          break;
      }
      notifyListeners();
    }
  }

  void toggleModel(String modelId, bool enabled) {
    if (modelId == _modelA.metadata.id) {
      _modelA.updateMetadata(_modelA.metadata.copyWith(enabled: enabled));
    } else if (modelId == _modelB.metadata.id) {
      _modelB.updateMetadata(_modelB.metadata.copyWith(enabled: enabled));
    } else if (modelId == _modelC.metadata.id) {
      _modelC.updateMetadata(_modelC.metadata.copyWith(enabled: enabled));
    }
    notifyListeners();
  }

  void clearSessionHistory() {
    _sessionHistory.clear();
    notifyListeners();
  }

  /// Save snapshot of the latest camera frame.
  Future<String?> takeSnapshot() async {
    final frame = _latestRawFrame;
    if (frame == null || frame.width <= 0 || frame.height <= 0) return null;

    try {
      final now = DateTime.now();
      final dateStr =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
          '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
      final fileName = 'infravision_$dateStr.jpg';
      final filePath = '${Directory.current.path}\\$fileName';

      final image = img.Image.fromBytes(
        width: frame.width,
        height: frame.height,
        bytes: frame.bytes.buffer,
        order: img.ChannelOrder.rgba,
      );

      final jpegBytes = img.encodeJpg(image, quality: 92);
      await File(filePath).writeAsBytes(jpegBytes);
      return filePath;
    } catch (e) {
      debugPrint('Snapshot error: $e');
      return null;
    }
  }

  void _processFrame(ProcessedFrame processedFrame) {
    _latestRawFrame = processedFrame.frame;
    TelemetryService.instance.recordCameraFrame();

    if (!_aiEnabled || _isProcessing) return;

    final now = DateTime.now().microsecondsSinceEpoch;
    final minIntervalUs = 1000000 ~/ _targetInferenceFps;

    if (now - _lastInferenceUs < minIntervalUs) return;

    _isProcessing = true;
    _lastInferenceUs = now;

    final totalSw = Stopwatch()..start();
    final frame = processedFrame.frame;

    try {
      // 1. Model A inference
      final swA = Stopwatch()..start();
      final detectionsA = _modelA.infer(frame, minConfidence: _confidenceThreshold);
      swA.stop();
      final latencyA = swA.elapsedMicroseconds / 1000.0;

      // 2. Model B inference
      final swB = Stopwatch()..start();
      final detectionsB = _modelB.infer(frame, minConfidence: _confidenceThreshold);
      swB.stop();
      final latencyB = swB.elapsedMicroseconds / 1000.0;

      // 3. Model C inference
      final swC = Stopwatch()..start();
      final detectionsC = _modelC.infer(frame, minConfidence: _confidenceThreshold);
      swC.stop();
      final latencyC = swC.elapsedMicroseconds / 1000.0;

      // 4. Ensemble Fusion
      final swEns = Stopwatch()..start();
      final activeModels = [
        _modelA.metadata,
        _modelB.metadata,
        _modelC.metadata,
      ];

      final unifiedDetections = _ensembleEngine.fuse(
        modelDetections: [detectionsA, detectionsB, detectionsC],
        activeModels: activeModels,
        timestamp: frame.timestamp,
        minUnifiedConfidence: _confidenceThreshold,
      );
      swEns.stop();
      final latencyEns = swEns.elapsedMicroseconds / 1000.0;

      // 5. Multi-Object Tracking
      final swTrack = Stopwatch()..start();
      final tracked = _trackingEnabled
          ? _tracker.update(unifiedDetections, timestamp: frame.timestamp)
          : unifiedDetections.asMap().entries.map((e) => MultiTrackObject(
                trackId: e.key + 1,
                className: e.value.className,
                box: e.value.box,
                confidence: e.value.confidence,
                colorHex: e.value.colorHex,
                contributingModelIds: e.value.contributingModelIds,
                agreementCount: e.value.agreementCount,
                activeModelCount: e.value.activeModelCount,
                firstSeenTimestamp: frame.timestamp,
                lastSeenTimestamp: frame.timestamp,
                state: TrackState.active,
              )).toList();
      swTrack.stop();
      final latencyTrack = swTrack.elapsedMicroseconds / 1000.0;

      totalSw.stop();
      final totalLatency = totalSw.elapsedMicroseconds / 1000.0;

      // 6. Update Session Detection Event Log
      _updateSessionHistory(tracked);

      // 7. Calculate measured AI FPS
      _inferenceCount++;
      if (_fpsWindowStartUs == 0) {
        _fpsWindowStartUs = now;
      } else {
        final elapsedUs = now - _fpsWindowStartUs;
        if (elapsedUs >= 1000000) {
          _measuredInferenceFps = _inferenceCount * 1000000.0 / elapsedUs;
          _inferenceCount = 0;
          _fpsWindowStartUs = now;
        }
      }

      TelemetryService.instance.recordInference(
        latencyMs: totalLatency,
        detectionsCount: unifiedDetections.length,
      );

      _latestResult = MultiModelVisionResult(
        unifiedDetections: unifiedDetections,
        trackedObjects: tracked,
        rawModelDetections: {
          _modelA.metadata.id: detectionsA,
          _modelB.metadata.id: detectionsB,
          _modelC.metadata.id: detectionsC,
        },
        modelALatencyMs: latencyA,
        modelBLatencyMs: latencyB,
        modelCLatencyMs: latencyC,
        ensembleLatencyMs: latencyEns,
        trackingLatencyMs: latencyTrack,
        totalLatencyMs: totalLatency,
        inferenceFps: _measuredInferenceFps,
        frameTimestamp: frame.timestamp,
        frameWidth: frame.width,
        frameHeight: frame.height,
      );

      notifyListeners();
    } catch (e, stack) {
      debugPrint('VisionService Level-2 error: $e\n$stack');
    } finally {
      _isProcessing = false;
    }
  }

  void _updateSessionHistory(List<MultiTrackObject> objects) {
    if (objects.isEmpty) return;
    final now = DateTime.now();

    for (final obj in objects) {
      final existingIndex = _sessionHistory.indexWhere(
        (e) => e.className.toLowerCase() == obj.className.toLowerCase(),
      );

      if (existingIndex >= 0) {
        _sessionHistory[existingIndex].count++;
      } else {
        if (_sessionHistory.length >= 100) {
          _sessionHistory.removeLast();
        }
        _sessionHistory.insert(
          0,
          DetectionHistoryEntry(
            className: obj.className,
            confidence: obj.confidence,
            timestamp: now,
            count: 1,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    stop();
    _modelA.dispose();
    _modelB.dispose();
    _modelC.dispose();
    super.dispose();
  }
}
