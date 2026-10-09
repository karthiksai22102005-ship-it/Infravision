/// ADAPTIVE PROCESSING PIPELINE — configurable stages, source-independent.
/// Different sources run different stage sets, but the stage implementations
/// are shared: no duplicated workflows per source.
library;

import '../intelligence/issue_intelligence_engine.dart';
import '../intelligence/models/observation.dart';
import 'field_events.dart';

class PipelineConfig {
  const PipelineConfig({
    this.minConfidence = 0.45,
    this.minStableFrames = 2,
    this.detectionCooldown = const Duration(seconds: 90),
    this.observationDuplicateWindow = const Duration(minutes: 30),
    this.duplicateDistanceMeters = 40,
    this.enrichWithGps = true,
    this.enrichWithContext = true,
  });

  // Centralized configuration — never hard-coded at call sites.
  final double minConfidence;
  final int minStableFrames;
  final Duration detectionCooldown;
  final Duration observationDuplicateWindow;
  final double duplicateDistanceMeters;
  final bool enrichWithGps;
  final bool enrichWithContext;

  /// Preset stage orders per source family — shared stages, no duplication.
  static const cameraStages = [
    ProcessingStage.validate,
    ProcessingStage.normalize,
    ProcessingStage.deduplicate,
    ProcessingStage.enrich,
    ProcessingStage.correlate,
  ];
  static const iotStages = [
    ProcessingStage.validate,
    ProcessingStage.deduplicate,
    ProcessingStage.enrich,
    ProcessingStage.correlate,
  ];
  static const manualStages = [
    ProcessingStage.validate,
    ProcessingStage.normalize,
    ProcessingStage.enrich,
    ProcessingStage.correlate,
  ];
}

enum ProcessingStage {
  validate,
  normalize,
  deduplicate,
  aggregate,
  enrich,
  correlate,
  persist,
  notify,
}

class PipelineResult {
  const PipelineResult(
      {required this.accepted, this.reason, this.observation});

  final bool accepted;
  final String? reason;
  final Observation? observation;
}

class ProcessingPipeline {
        ProcessingPipeline({PipelineConfig? config})
      : config = config ?? const PipelineConfig();

  PipelineConfig config;

  // LEVEL 1+2 dedup state. (Level 3 = issue correlation, which is the
  // existing IssueMatchingEngine — deliberately a separate responsibility.)
  final Map<String, DateTime> _lastByTrack = {};
  final List<Observation> _recentObservations = [];

  /// Runs [event] through the configured stages.
  PipelineResult process(NormalizedEvent event,
      {List<ProcessingStage>? stages}) {
    final pipe = stages ?? _defaultStagesFor(event);

    for (final stage in pipe) {
      switch (stage) {
        case ProcessingStage.validate:
          final err = _validate(event);
          if (err != null) {
            event.processingStatus = ProcessingStatus.rejected;
            return PipelineResult(accepted: false, reason: err);
          }
          event.processingStatus = ProcessingStatus.validated;

        case ProcessingStage.normalize:
          event.processingStatus = ProcessingStatus.normalized;

        case ProcessingStage.deduplicate:
          final reason = _deduplicate(event);
          if (reason != null) {
            event.processingStatus = ProcessingStatus.rejected;
            return PipelineResult(accepted: false, reason: reason);
          }
          event.processingStatus = ProcessingStatus.deduplicated;

        case ProcessingStage.aggregate:
          event.processingStatus = ProcessingStatus.aggregated;

        case ProcessingStage.enrich:
          _enrich(event);
          event.processingStatus = ProcessingStatus.enriched;

        case ProcessingStage.correlate:
          final observation = _toObservation(event);
          IssueIntelligenceEngine.instance.submitObservation(observation);
          event.processingStatus = ProcessingStatus.observationCreated;
          event.syncState = SyncState.synced;
          _recentObservations.add(observation);
          FieldEventBus.instance.publish(event);
          return PipelineResult(accepted: true, observation: observation);

        case ProcessingStage.persist:
        case ProcessingStage.notify:
          break; // owned by intelligence engine + notification service
      }
    }
    return const PipelineResult(accepted: true);
  }

  List<ProcessingStage> _defaultStagesFor(NormalizedEvent event) {
    switch (event.sourceCategory) {
      case 'iot':
        return PipelineConfig.iotStages;
      case 'human':
        return PipelineConfig.manualStages;
      default:
        return PipelineConfig.cameraStages;
    }
  }

  String? _validate(NormalizedEvent e) {
    if (e.eventType == FieldEventType.cameraFrameReceived) {
      return 'raw frames never enter the intelligence pipeline';
    }
    if ((e.confidence ?? 1.0) < config.minConfidence) {
      return 'confidence ${e.confidence} below ${config.minConfidence}';
    }
    final stable = (e.payload['stableFrames'] as num?)?.toInt();
    if (stable != null && stable < config.minStableFrames) {
      return 'only $stable stable frame(s), need ${config.minStableFrames}';
    }
    return null;
  }

  String? _deduplicate(NormalizedEvent e) {
    // LEVEL 1 — track/frame level: same tracked object inside cooldown.
    final last = _lastByTrack[e.sourceId];
    if (last != null &&
        e.timestamp.difference(last).abs() < config.detectionCooldown) {
      return 'track ${e.sourceId} inside detection cooldown';
    }
    // LEVEL 2 — observation level: same source near-same place, short window.
    for (final o in _recentObservations) {
      final sameSource = o.sourceId == e.eventId ? false : o.sourceId.endsWith(e.eventId) || e.eventId.contains(o.sourceId);
            // Level 2 — observation level: same source or near-same place within
      // a short time window triggers deduplication.
      final near = (e.latitude != null && e.longitude != null) &&
          _distance(o.latitude, o.longitude,
                  e.latitude!, e.longitude!) <
              config.duplicateDistanceMeters;
      final fresh = e.timestamp.difference(o.timestamp).abs() <
          config.observationDuplicateWindow;
      if (near && fresh) {
        return 'duplicate observation within distance+time window';
      }
      if (sameSource && fresh) {
        return 'duplicate observation from same source within window';
      }
    }
    _lastByTrack[e.sourceId] = e.timestamp;
    return null;
  }

  void _enrich(NormalizedEvent e) {
    // Partial data is fine — the engine works with whatever exists.
    e.metadata['enrichedAt'] = DateTime.now().toIso8601String();
    if (config.enrichWithGps && e.latitude != null) {
      e.metadata['hasGps'] = true;
    }
    if (config.enrichWithContext) {
      e.metadata['nearbyOpenIssues'] =
          IssueIntelligenceEngine.instance.openIssues.length;
    }
  }

  Observation _toObservation(NormalizedEvent e) {
    final rawType = (e.payload['label'] ??
            e.payload['issueType'] ??
            e.payload['sensorType']) as String? ??
        'Unclassified';
    return Observation(
      observationId: 'OBS-F-${e.eventId}',
      sourceType: switch (e.sourceCategory) {
        'iot' => ObservationSourceType.aiBatchAnalysis, // sensor telemetry
        'human' => ObservationSourceType.fieldAgent,
        'edge-ai' => ObservationSourceType.aiLiveDetection,
        _ => ObservationSourceType.externalSystem,
      },
      sourceId: e.eventId,
      timestamp: e.timestamp,
      latitude: e.latitude ?? 0,
      longitude: e.longitude ?? 0,
      locationAccuracy: e.locationAccuracy,
      media: e.evidenceReferences,
      visualFeatures: const {},
      detectedIssueType: rawType,
      classification: rawType,
      aiConfidence: e.confidence,
      userDescription: e.payload['description'] as String? ?? '',
      contextData: {
        'address': e.payload['address'],
        'assetId': e.payload['assetId'],
        'deviceId': e.deviceId,
        'mode': e.mode.name,
      },
      deviceInformation: e.deviceId,
    );
  }

  static double _distance(lat1, lon1, lat2, lon2) {
    final dLat = (lat2 - lat1) * 111320;
    final dLon = (lon2 - lon1) * 111320 * 0.94;
    final s = dLat * dLat + dLon * dLon;
    if (s == 0) return 0;
    var r = s;
    for (var i = 0; i < 24; i++) {
      r = 0.5 * (r + s / r);
    }
    return r;
  }
}

