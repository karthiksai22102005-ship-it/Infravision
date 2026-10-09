/// FIELD INTELLIGENCE ORCHESTRATOR â€” the non-UI composition root that wires
/// every existing source (Live CV Sweep, Batch Route, Offline Queue,
/// Checklist) into the shared observation -> correlation -> lifecycle
/// pipeline. The four Field Intelligence tabs are left untouched; this class
/// merely makes them observable by the domain-independent stack.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../intelligence/models/observation.dart';
import '../intelligence/issue_intelligence_engine.dart';
import 'adapters.dart';
import 'field_events.dart';
import 'iot.dart';
import 'pipeline.dart';

/// Globally-unique session so every signal within a field run is attributable
/// to one contextual container (survives GPS gaps, device gaps, offline).
class FieldSession {
  FieldSession({required this.sessionId, DateTime? startedAt})
      : startedAt = startedAt ?? DateTime.now();

  final String sessionId;
  final DateTime startedAt;
  DateTime? endedAt;
  final List<String> observationIds = [];

  bool get active => endedAt == null;

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt?.toIso8601String(),
        'observationIds': observationIds,
      };

  factory FieldSession.fromJson(Map<String, dynamic> json) => FieldSession(
        sessionId: json['sessionId'] as String,
        startedAt: DateTime.parse(json['startedAt'] as String),
      )..endedAt = json['endedAt'] != null
          ? DateTime.parse(json['endedAt'] as String)
          : null;
}

/// Per-entity local ledger entry for offline-first idempotent sync. Each
/// normalized event carries a deterministic eventId so replay never produces
/// duplicate observations or duplicate physical issues.
class SyncLedgerEntry {
  SyncLedgerEntry({
    required this.eventId,
    this.firstSeen = SyncState.local,
    this.createdAt,
  });

  final String eventId;
  final DateTime? createdAt;
  SyncState firstSeen;

  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'createdAt': createdAt?.toIso8601String(),
        'firstSeen': firstSeen.name,
      };

  factory SyncLedgerEntry.fromJson(Map<String, dynamic> json) =>
      SyncLedgerEntry(
        eventId: json['eventId'] as String,
        firstSeen: SyncState.values.firstWhere(
          (s) => s.name == json['firstSeen'],
          orElse: () => SyncState.local,
        ),
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String)
            : null,
      );
}
class AdaptiveMissionItem {
  AdaptiveMissionItem({
    required this.id,
    required this.priority,
    required this.title,
    required this.category,
    required this.reason,
    required this.targetId,
    this.location,
    this.dueBy,
    this.mode = DataSourceMode.real,
  });

  final String id;
  final MissionPriority priority;
  final String title;
  final String category;
  final String reason;
  final String targetId;
  final (double? lat, double? lng)? location;
  final DateTime? dueBy;
  final DataSourceMode mode;

  Map<String, dynamic> toJson() => {
        'id': id,
        'priority': priority.name,
        'title': title,
        'category': category,
        'reason': reason,
        'targetId': targetId,
        'lat': location?.$1,
        'lng': location?.$2,
        'dueBy': dueBy?.toIso8601String(),
        'mode': mode.name,
      };

  factory AdaptiveMissionItem.fromJson(Map<String, dynamic> json) {
    final lat = (json['lat'] as num?)?.toDouble();
    final lng = (json['lng'] as num?)?.toDouble();
    return AdaptiveMissionItem(
      id: json['id'] as String,
      priority: MissionPriority.values.firstWhere(
        (p) => p.name == json['priority'],
        orElse: () => MissionPriority.normal,
      ),
      title: json['title'] as String,
      category: json['category'] as String,
      reason: json['reason'] as String,
      targetId: json['targetId'] as String,
      location: lat != null && lng != null ? (lat, lng) : null,
      dueBy: json['dueBy'] != null
          ? DateTime.parse(json['dueBy'] as String)
          : null,
      mode: DataSourceMode.values.firstWhere(
        (m) => m.name == json['mode'],
        orElse: () => DataSourceMode.real,
      ),
    );
  }
}


enum MissionPriority { critical, high, normal, low }

/// Structured internal diagnostics â€” never surfaced raw to normal users.
class FieldDiagnostics {
  FieldDiagnostics();
  final List<FieldErrorEntry> errors = [];
  final Map<String, int> counters = {};

  void record(String key, {int by = 1}) =>
      counters.update(key, (v) => v + by, ifAbsent: () => by);

  void error(String category, Object error, [StackTrace? st]) {
    errors.add(FieldErrorEntry(
        category: category, error: error.toString(), timestamp: DateTime.now()));
    record('errors_$category');
  }
}

class FieldErrorEntry {
  FieldErrorEntry({
    required this.category,
    required this.error,
    required this.timestamp,
  });

  final String category;
  final String error;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
        'category': category,
        'error': error,
        'timestamp': timestamp.toIso8601String(),
      };
}
/// THE ORCHESTRATOR â€” boots the field-intelligence layer and owns the
/// session lifecycle, sync ledger, adapter registry and IoT providers.
class FieldOrchestrator {
  FieldOrchestrator._() {
    _diagnostics = FieldDiagnostics();
  }

  static final FieldOrchestrator instance = FieldOrchestrator._();

  late final FieldDiagnostics _diagnostics;
  FieldDiagnostics get diagnostics => _diagnostics;

  FieldSession? _currentSession;
  FieldSession? get currentSession => _currentSession;

  bool _ready = false;
  bool get isReady => _ready;

  Directory? _baseDir;
  File? _ledgerFile;
  File? _sessionFile;

  late final ProcessingPipeline _pipeline;

  final Map<String, SyncLedgerEntry> _ledger = {};
  final List<AdaptiveMissionItem> _missions = [];
  final List<DeviceProvider> _deviceProviders = [];

  Future<void> initialize({
    bool useSimulation = true,
    String? basePath,
  }) async {
    if (_ready) return;
    try {
      _baseDir = _resolveBaseDir(basePath);
      await _baseDir!.create(recursive: true);
      _ledgerFile = File('${_baseDir!.path}/ledger.json');
      _sessionFile = File('${_baseDir!.path}/session.json');
      await _recover();

      _pipeline = ProcessingPipeline(
        config: const PipelineConfig(
          minConfidence: 0.45,
          minStableFrames: 2,
          detectionCooldown: Duration(seconds: 90),
          observationDuplicateWindow: Duration(minutes: 30),
          duplicateDistanceMeters: 40,
        ),
      );

      DataSourceRegistry.instance.register(const YoloDetectionAdapter());
      DataSourceRegistry.instance.register(const IoTDeviceAdapter());
      DataSourceRegistry.instance.register(const ManualInputAdapter());
      DataSourceRegistry.instance.register(const BatchMediaAdapter());

      if (useSimulation) {
        _deviceProviders.add(SimulationDeviceProvider());
      }

      _startSession();

      _ready = true;
      _diagnostics.record('orchestrator_ready');
      debugPrint('FieldOrchestrator: ready with '
          '${DataSourceRegistry.instance.registeredTypes.length} adapter(s) '
          'and ${_deviceProviders.length} device provider(s).');
    } catch (e, st) {
      _diagnostics.error('orchestrator_init', e, st);
      _ready = true;
    }
  }

  void _startSession() {
    _currentSession = FieldSession(
        sessionId: 'SESSION-${DateTime.now().millisecondsSinceEpoch}');
    _persistSession();
  }

  Future<void> endSession() async {
    _currentSession?.endedAt = DateTime.now();
    await _persistSession();
  }

  Future<void> _persistSession() async {
    if (_baseDir == null || _currentSession == null) return;
    try {
      await _sessionFile!.writeAsString(
          jsonEncode(_currentSession!.toJson()));
    } catch (e, st) {
      _diagnostics.error('session_persist', e, st);
    }
  }

  Future<void> _recover() async {
    try {
      if (await _ledgerFile!.exists()) {
        final json = jsonDecode(await _ledgerFile!.readAsString());
        for (final e in (json as List<dynamic>)) {
          final entry = SyncLedgerEntry.fromJson(e as Map<String, dynamic>);
          _ledger[entry.eventId] = entry;
        }
      }
      if (await _sessionFile!.exists()) {
        _currentSession = FieldSession.fromJson(
            jsonDecode(await _sessionFile!.readAsString()) as Map<String, dynamic>);
      }
    } catch (e, st) {
      _diagnostics.error('recovery', e, st);
    }
  }

  Future<void> _persistLedger() async {
    if (_ledgerFile == null) return;
    try {
      await _ledgerFile!.writeAsString(
          jsonEncode(_ledger.values.map((e) => e.toJson()).toList()));
    } catch (e, st) {
      _diagnostics.error('ledger_persist', e, st);
    }
  }
  void processEvent(NormalizedEvent event) {
    _ledger[event.eventId] ??=
        SyncLedgerEntry(eventId: event.eventId, createdAt: DateTime.now());
    _currentSession?.observationIds.add(event.eventId);

    PipelineResult result;
    try {
      result = _pipeline.process(event);
    } catch (e, st) {
      _diagnostics.error('pipeline_process', e, st);
      return;
    }

    if (!result.accepted || result.observation == null) {
      _diagnostics.record('events_rejected');
      _persistLedger();
      return;
    }

    final observation = result.observation!;
    _diagnostics.record('events_processed');

    try {
      final outcome =
          IssueIntelligenceEngine.instance.submitObservation(observation);
      if (outcome.createdNew) {
        _diagnostics.record('issues_created');
      } else if (outcome.matchResult.resultType.name == 'matched') {
        _diagnostics.record('issues_matched');
      } else {
        _diagnostics.record('issues_uncertain');
      }
      _maybeGenerateMission(event, observation);
    } catch (e, st) {
      _diagnostics.error('submit_observation', e, st);
    }

    _persistSession();
    _persistLedger();
  }

  void _maybeGenerateMission(
      NormalizedEvent event, Observation observation) {
    final kind = event.payload['label'] ?? event.payload['issueType'];
    if (kind == null) return;
    final id = 'mission-${event.eventId}';
    if (_missions.any((m) => m.id == id)) return;
    final pri = (event.confidence ?? 0) >= 0.8
        ? MissionPriority.critical
        : (event.confidence ?? 0) >= 0.6
            ? MissionPriority.high
            : MissionPriority.normal;
    _missions.insert(
        0,
        AdaptiveMissionItem(
          id: id,
          priority: pri,
          title: 'Investigate: $kind',
          category: event.sourceCategory,
          reason: 'Observation ${event.eventId} requires field confirmation.',
          targetId: event.eventId,
          location: (event.latitude, event.longitude),
          mode: event.mode,
        ));
  }

  Future<List<IoTDevice>> discoverIoTDevices() async {
    final all = <IoTDevice>[];
    for (final p in _deviceProviders) {
      try {
        all.addAll(await p.discoverDevices());
      } catch (e, st) {
        _diagnostics.error('device_discovery', e, st);
      }
    }
    return all;
  }

  Stream<NormalizedEvent> streamIoTReadings() async* {
    for (final provider in _deviceProviders) {
      try {
        for (final device in await provider.discoverDevices()) {
          await for (final reading in provider.readings([device])) {
            final evt = _readingToEvent(reading, provider.providerId);
            processEvent(evt);
            yield evt;
          }
        }
      } catch (e, st) {
        _diagnostics.error('iot_stream', e, st);
      }
    }
  }

  NormalizedEvent _readingToEvent(SensorReading reading, String providerId) {
    final quality = reading.quality;
    final isAnomaly = quality != 'good' && reading.value.abs() > 0.6;
    final severity = reading.metadata['severity'] as String?;
    return NormalizedEvent(
      eventId: 'iot-${reading.deviceId}-${reading.sensorType}-'
          '${reading.timestamp.millisecondsSinceEpoch ~/ 60000}'
          '${isAnomaly ? '-a' : ''}',
      sourceType: 'iot',
      sourceId: reading.deviceId,
      eventType: isAnomaly
          ? FieldEventType.sensorAnomalyDetected
          : FieldEventType.sensorReadingReceived,
      timestamp: reading.timestamp,
      sourceCategory: 'iot',
      deviceId: reading.deviceId,
      latitude: reading.latitude,
      longitude: reading.longitude,
      confidence: quality == 'good' ? 0.9 : 0.6,
      payload: {
        'sensorType': reading.sensorType,
        'value': reading.value,
        'unit': reading.unit,
        if (severity != null) 'severity': severity,
        'assetId': reading.assetId,
        'quality': quality,
        'providerId': providerId,
      },
      mode: DataSourceMode.real,
    );
  }

  Stream<NormalizedEvent> fromYoloDetection(Map<String, dynamic> raw) =>
      DataSourceRegistry.instance.byType('yolo')?.adapt(raw) ??
      const Stream.empty();

  Stream<NormalizedEvent> fromBatchMedia(Map<String, dynamic> raw) =>
      DataSourceRegistry.instance.byType('batch')?.adapt(raw) ??
      const Stream.empty();

  Stream<NormalizedEvent> fromManualInput(Map<String, dynamic> raw) =>
      DataSourceRegistry.instance.byType('manual')?.adapt(raw) ??
      const Stream.empty();

  Directory _resolveBaseDir(String? basePath) {
    if (basePath != null) return Directory(basePath);
    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'] ??
          Platform.environment['APPDATA'] ??
          'C:/Users/Dell/AppData/Local';
      return Directory('$localAppData/InfraVision/field');
    }
    return Directory.systemTemp.createTempSync('infravision_field_');
  }

  List<AdaptiveMissionItem> get missions => List.unmodifiable(_missions);
  List<SyncLedgerEntry> get ledger => List.unmodifiable(_ledger.values);
}