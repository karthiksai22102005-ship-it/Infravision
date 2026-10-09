/// FIELD EVENT CONTRACT — the source-independent normalized data structure.
/// Every adapter (camera, YOLO, IoT, manual, batch, external API) produces
/// NormalizedEvents; the processing pipeline only ever sees these.
library;

import 'dart:async';

/// Explicit data provenance — simulation is NEVER presented as real hardware.
enum DataSourceMode { real, simulated, mock }

enum FieldEventType {
  cameraFrameReceived,
  aiDetectionCreated,
  objectTrackStable,
  sensorReadingReceived,
  sensorAnomalyDetected,
  manualInputReceived,
  batchMediaProcessed,
  observationCreated,
  observationEnriched,
  issueCandidatesFound,
  issueMatched,
  newIssueCreated,
  matchUncertain,
  verificationRequested,
  resolutionSubmitted,
  issueReopened,
  issueResolved,
}

enum ProcessingStatus { received, validated, normalized, deduplicated, aggregated, enriched, correlated, observationCreated, rejected }

/// Offline-first synchronization states.
enum SyncState { local, queued, syncing, synced, processing, failed, conflict, retry }

class NormalizedEvent {
  NormalizedEvent({
    required this.eventId,
    required this.sourceType,
    required this.sourceId,
    required this.eventType,
    required this.timestamp,
    this.sourceCategory = 'field',
    this.deviceId,
    this.actorId,
    this.sessionId,
    this.latitude,
    this.longitude,
    this.locationAccuracy,
    this.payload = const {},
    this.confidence,
    this.metadata = const {},
    this.evidenceReferences = const [],
    this.processingStatus = ProcessingStatus.received,
    this.syncState = SyncState.local,
    this.schemaVersion = 1,
    this.mode = DataSourceMode.real,
  });

  /// Deterministic ID: adapters should derive it from content so repeated
  /// delivery of the same signal is idempotent across syncs.
  final String eventId;
  final String sourceType;
  final String sourceId;
  final FieldEventType eventType;
  final DateTime timestamp;
  final String sourceCategory;
  final String? deviceId;
  final String? actorId;
  final String? sessionId;

  // Stable core — all optional so partial data never breaks the pipeline.
  final double? latitude;
  final double? longitude;
  final double? locationAccuracy;

  /// Flexible, source-specific, schema-evolvable payload.
  final Map<String, dynamic> payload;
  final double? confidence;
  final Map<String, dynamic> metadata;
  final List<String> evidenceReferences;

  ProcessingStatus processingStatus;
  SyncState syncState;
  final int schemaVersion;
  final DataSourceMode mode;

  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'sourceType': sourceType,
        'sourceId': sourceId,
        'eventType': eventType.name,
        'timestamp': timestamp.toIso8601String(),
        'sourceCategory': sourceCategory,
        'deviceId': deviceId,
        'actorId': actorId,
        'sessionId': sessionId,
        'latitude': latitude,
        'longitude': longitude,
        'locationAccuracy': locationAccuracy,
        'payload': payload,
        'confidence': confidence,
        'metadata': metadata,
        'evidenceReferences': evidenceReferences,
        'processingStatus': processingStatus.name,
        'syncState': syncState.name,
        'schemaVersion': schemaVersion,
        'mode': mode.name,
      };

  factory NormalizedEvent.fromJson(Map<String, dynamic> json) =>
      NormalizedEvent(
        eventId: json['eventId'] as String,
        sourceType: json['sourceType'] as String,
        sourceId: json['sourceId'] as String,
        eventType: FieldEventType.values
            .firstWhere((e) => e.name == json['eventType'],
                orElse: () => FieldEventType.manualInputReceived),
        timestamp: DateTime.parse(json['timestamp'] as String),
        sourceCategory: json['sourceCategory'] as String? ?? 'field',
        deviceId: json['deviceId'] as String?,
        actorId: json['actorId'] as String?,
        sessionId: json['sessionId'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        locationAccuracy: (json['locationAccuracy'] as num?)?.toDouble(),
        payload: (json['payload'] as Map<String, dynamic>?) ?? const {},
        confidence: (json['confidence'] as num?)?.toDouble(),
        metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
        evidenceReferences:
            (json['evidenceReferences'] as List<dynamic>?)?.cast<String>() ??
                const [],
        processingStatus: ProcessingStatus.values.firstWhere(
            (p) => p.name == json['processingStatus'],
            orElse: () => ProcessingStatus.received),
        syncState: SyncState.values.firstWhere(
            (s) => s.name == json['syncState'],
            orElse: () => SyncState.local),
        schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
        mode: DataSourceMode.values.firstWhere(
            (m) => m.name == json['mode'],
            orElse: () => DataSourceMode.real),
      );
}

/// Lightweight local event bus — producers and consumers stay decoupled
/// without any distributed infrastructure.
class FieldEventBus {
  FieldEventBus._();
  static final FieldEventBus instance = FieldEventBus._();

  final _controller = StreamController<NormalizedEvent>.broadcast();
  Stream<NormalizedEvent> get stream => _controller.stream;

  void publish(NormalizedEvent event) {
    if (!_controller.isClosed) _controller.add(event);
  }

  Future<void> dispose() => _controller.close();
}
