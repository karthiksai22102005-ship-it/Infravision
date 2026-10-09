/// SOURCE ADAPTER ARCHITECTURE — the only seam new data sources ever touch.
/// Adding a source = implement [DataSourceAdapter] + register it. The
/// matching engine, PhysicalIssue model, lifecycle engine and all four portal
/// tabs are never modified for a new source.
library;

import 'field_events.dart';

/// Every data source implements this and yields NormalizedEvents.
abstract class DataSourceAdapter {
  String get sourceType;
  DataSourceMode get mode;

  /// Adapters decide their own validation; the pipeline re-validates anyway.
  Stream<NormalizedEvent> adapt(Map<String, dynamic> raw);
}

/// Registry — REGISTER → ADAPT → CONFIGURE → PROCESS.
class DataSourceRegistry {
  DataSourceRegistry._();
  static final DataSourceRegistry instance = DataSourceRegistry._();

  final Map<String, DataSourceAdapter> _adapters = {};

  void register(DataSourceAdapter adapter) =>
      _adapters[adapter.sourceType] = adapter;

  DataSourceAdapter? byType(String sourceType) => _adapters[sourceType];

  Iterable<String> get registeredTypes => _adapters.keys;
}

/// YOLO adapter — views the existing ensemble output (UnifiedDetection) with
/// full import isolation: the vision stack is adapted via raw maps so this
/// layer never couples to model internals.
class YoloDetectionAdapter implements DataSourceAdapter {
    const YoloDetectionAdapter({
    this.mode = DataSourceMode.real,
    this.actorId = 'field-agent',
  });

  @override
  final DataSourceMode mode;
  final String? actorId;

  @override
  String get sourceType => 'yolo';

  @override
  Stream<NormalizedEvent> adapt(Map<String, dynamic> raw) async* {
    final label = raw['label'] as String?;
    if (label == null || (raw['confidence'] as num?) == null) return;
    final observedAt = (raw['observedAt'] as DateTime?) ?? DateTime.now();
    final trackId = raw['trackId'] as String? ?? label;

    yield NormalizedEvent(
      eventId:
          'yolo-$trackId-${observedAt.millisecondsSinceEpoch ~/ 30000}',
      sourceType: sourceType,
      sourceId: trackId,
      eventType: FieldEventType.aiDetectionCreated,
      timestamp: observedAt,
      sourceCategory: 'edge-ai',
      actorId: actorId,
      sessionId: raw['sessionId'] as String?,
      latitude: (raw['latitude'] as num?)?.toDouble(),
      longitude: (raw['longitude'] as num?)?.toDouble(),
      locationAccuracy: (raw['locationAccuracy'] as num?)?.toDouble(),
      confidence: (raw['confidence'] as num?)!.toDouble(),
      payload: {
        'label': label,
        'stableFrames': (raw['stableFrames'] as num?)?.toInt() ?? 1,
        if (raw['bbox'] != null) 'bbox': raw['bbox'],
      },
      metadata: {
        'agreementRatio': raw['agreementRatio'],
        'contributingModels': raw['contributingModels'],
      },
      evidenceReferences: [
        if (raw['evidencePath'] != null) raw['evidencePath'] as String,
      ],
      mode: mode,
    );
  }
}

/// Generic IoT device adapter — consumes sensor readings from any
/// [DeviceProvider] (simulation now; MQTT/HTTP/BLE later via same shape).
class IoTDeviceAdapter implements DataSourceAdapter {
    const IoTDeviceAdapter({this.mode = DataSourceMode.real});

  @override
  final DataSourceMode mode;

  @override
  String get sourceType => 'iot';

  @override
  Stream<NormalizedEvent> adapt(Map<String, dynamic> raw) async* {
    final deviceId = raw['deviceId'] as String?;
    if (deviceId == null) return;
    final ts = (raw['timestamp'] as DateTime?) ?? DateTime.now();
    final anomaly = raw['anomaly'] as bool? ?? false;
    yield NormalizedEvent(
      eventId: 'iot-$deviceId-${raw['sensorType']}-'
          '${ts.millisecondsSinceEpoch ~/ 60000}${anomaly ? '-a' : ''}',
      sourceType: sourceType,
      sourceId: deviceId,
      eventType: anomaly
          ? FieldEventType.sensorAnomalyDetected
          : FieldEventType.sensorReadingReceived,
      timestamp: ts,
      sourceCategory: 'iot',
      deviceId: deviceId,
      latitude: (raw['latitude'] as num?)?.toDouble(),
      longitude: (raw['longitude'] as num?)?.toDouble(),
      confidence: (raw['confidence'] as num?)?.toDouble() ?? 0.7,
      payload: {
        'sensorType': raw['sensorType'],
        'value': raw['value'],
        'unit': raw['unit'],
        'severity': raw['severity'],
        'assetId': raw['assetId'],
      },
      metadata: {
        'quality': raw['quality'],
        'manufacturer': raw['manufacturer'],
      },
      mode: raw['mode'] is DataSourceMode ? raw['mode'] as DataSourceMode : mode,
    );
  }
}

/// Manual field inspection / checklist input.
class ManualInputAdapter implements DataSourceAdapter {
    const ManualInputAdapter({this.mode = DataSourceMode.real});

  @override
  final DataSourceMode mode;

  @override
  String get sourceType => 'manual';

  @override
  Stream<NormalizedEvent> adapt(Map<String, dynamic> raw) async* {
    if (raw['sourceId'] == null) return;
    yield NormalizedEvent(
      eventId:
          'manual-${raw['sourceId']}-${DateTime.now().millisecondsSinceEpoch}',
      sourceType: sourceType,
      sourceId: raw['sourceId'] as String,
      eventType: FieldEventType.manualInputReceived,
      timestamp: (raw['timestamp'] as DateTime?) ?? DateTime.now(),
      sourceCategory: 'human',
      actorId: raw['actorId'] as String?,
      latitude: (raw['latitude'] as num?)?.toDouble(),
      longitude: (raw['longitude'] as num?)?.toDouble(),
      locationAccuracy: (raw['locationAccuracy'] as num?)?.toDouble(),
      confidence: 1.0,
      payload: {
        'description': raw['description'],
        'issueType': raw['issueType'],
      },
      evidenceReferences:
          (raw['evidencePaths'] as List<dynamic>?)?.cast<String>() ?? const [],
      mode: mode,
    );
  }
}

/// Batch Route media (video / image collections) — same pipeline, different
/// input shape. Drone footage and sensor logs plug in identically later.
class BatchMediaAdapter implements DataSourceAdapter {
    const BatchMediaAdapter({this.mode = DataSourceMode.real});

  @override
  final DataSourceMode mode;

  @override
  String get sourceType => 'batch';

  @override
  Stream<NormalizedEvent> adapt(Map<String, dynamic> raw) async* {
    if (raw['sourceId'] == null) return;
    yield NormalizedEvent(
      eventId:
          'batch-${raw['sourceId']}-${DateTime.now().millisecondsSinceEpoch}',
      sourceType: sourceType,
      sourceId: raw['sourceId'] as String,
      eventType: FieldEventType.batchMediaProcessed,
      timestamp: (raw['timestamp'] as DateTime?) ?? DateTime.now(),
      sourceCategory: 'edge-ai',
      actorId: raw['actorId'] as String?,
      latitude: (raw['latitude'] as num?)?.toDouble(),
      longitude: (raw['longitude'] as num?)?.toDouble(),
      confidence: (raw['confidence'] as num?)?.toDouble(),
      payload: {
        'label': raw['label'],
        'mediaPath': raw['mediaPath'],
        'routeId': raw['routeId'],
      },
      evidenceReferences: [
        if (raw['mediaPath'] != null) raw['mediaPath'] as String,
      ],
      mode: mode,
    );
  }
}

