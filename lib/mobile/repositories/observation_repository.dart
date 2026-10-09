import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../config/mobile_config.dart';
import '../core/app_logger.dart';
import '../core/id_generator.dart';
import '../core/query.dart';
import '../core/result.dart';
import '../data/evidence_store.dart';
import '../data/local_database.dart';
import '../models/analysis.dart';
import '../models/evidence.dart';
import '../models/observation.dart';
import '../services/analysis_service.dart';
import '../services/device_capability_service.dart';
import '../services/duplicate_service.dart';
import '../services/image_pipeline_service.dart';
import '../services/network_service.dart';
import '../services/priority_service.dart';
import '../services/severity_service.dart';

/// Result of ingesting one evidence item, including the measured quality gate
/// and the on-device analysis (which may honestly report "unavailable").
class EvidenceIngest {
  const EvidenceIngest({
    required this.evidence,
    required this.quality,
    required this.analysis,
  });

  final Evidence evidence;
  final QualityReport quality;
  final AnalysisResult analysis;
}

/// Offline-first repository for observations and evidence (§69).
///
/// UI -> ObservationRepository -> ApiClient -> backend. The repository owns
/// the local database, the evidence vault, the assessment engines and the
/// sync queue so no widget ever talks HTTP directly.
class ObservationRepository extends ChangeNotifier {
  ObservationRepository({
    required this.database,
    required this.evidenceStore,
    required this.network,
    required this.capabilities,
    required this.analysis,
    required this.pipeline,
  });

  final LocalDatabase database;
  final EvidenceStore evidenceStore;
  final NetworkService network;
  final DeviceCapabilityService capabilities;
  final AnalysisService analysis;
  final ImagePipelineService pipeline;

  ApiClient? _client;
  String _baseUrl = '';
  String _observerId = 'field-observer';
  bool _syncRunning = false;
  String? _lastSyncMessage;
  double _uploadProgress = 0;

  ApiClient get client => _client ?? ApiClient(baseUrl: _baseUrl);
  String get baseUrl => _baseUrl;
  String get observerId => _observerId;
  bool get isSyncing => _syncRunning;
  String? get lastSyncMessage => _lastSyncMessage;
  double get uploadProgress => _uploadProgress;
  bool get backendConfigured => client.isConfigured;
  int get pendingCount => database.pendingSync().length;

  Future<void> initialize() async {
    final Directory root = await evidenceStore.root();
    await database.open();

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString('obs.baseUrl') ??
        (MobileConfig.compileTimeApiBaseUrl.isNotEmpty
            ? MobileConfig.compileTimeApiBaseUrl
            : '');
    String? storedObserver = prefs.getString('obs.observerId');
    if (storedObserver == null) {
      storedObserver = IdGenerator.uuid();
      await prefs.setString('obs.observerId', storedObserver);
    }
    _observerId = storedObserver;
    _client?.dispose();
    _client = ApiClient(
      baseUrl: _baseUrl,
      authToken: prefs.getString('obs.token'),
    );

    await analysis.prepare(workDirectory: root);
    AppLog.i(
      'Repo',
      'Initialized: ${database.observations.length} observations, '
      'backend=${backendConfigured ? 'configured' : 'not configured'}',
    );
    notifyListeners();
  }

  Future<void> setBackendUrl(String url) async {
    final String trimmed = url.trim();
    final Uri? parsed = Uri.tryParse(trimmed);
    if (trimmed.isNotEmpty && (parsed == null || !parsed.hasScheme)) {
      throw const FormatException('Enter a full URL such as https://host');
    }
    _baseUrl = trimmed;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('obs.baseUrl', trimmed);
    _client?.dispose();
    _client = ApiClient(baseUrl: _baseUrl, authToken: prefs.getString('obs.token'));
    notifyListeners();
  }

  Future<void> setAuthToken(String token) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (token.isEmpty) {
      await prefs.remove('obs.token');
    } else {
      await prefs.setString('obs.token', token);
    }
    _client?.dispose();
    _client = ApiClient(baseUrl: _baseUrl, authToken: token.isEmpty ? null : token);
    notifyListeners();
  }

  Future<String> loadToken() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('obs.token') ?? '';
  }
  // ---------------------------------------------------------------------------
  // Evidence ingestion (§13/§14/§17/§18)
  // ---------------------------------------------------------------------------

  /// Imports one captured or picked file as evidence of an observation.
  Future<Result<EvidenceIngest>> ingestEvidence({
    required String observationId,
    required File file,
    required EvidenceType type,
    EvidenceRole role = EvidenceRole.additional,
    String captureSource = 'device-camera',
    DateTime? capturedAt,
    Duration measuredVideoDuration = Duration.zero,
    LocationFix? location,
    bool runAnalysis = true,
  }) async {
    final Failure? invalid = await pipeline.validateFile(file);
    if (invalid != null) return Err<EvidenceIngest>(invalid);

    final String evidenceId = IdGenerator.evidenceId();
    final String extension =
        file.path.split('.').last.toLowerCase().replaceAll('.', '');
    final DateTime captured = capturedAt ?? DateTime.now();

    final StoredCapture stored;
    try {
      stored = await evidenceStore.importOriginal(
        observationId: observationId,
        evidenceId: evidenceId,
        source: file,
        type: type,
        extension: extension,
        mimeType: type == EvidenceType.video ? 'video/mp4' : 'image/jpeg',
      );
    } catch (e) {
      AppLog.e('Repo', 'Evidence import failed: $e');
      return const Err<EvidenceIngest>(
        Failure('storage_failed', 'The file could not be stored.'),
      );
    }

    Evidence evidence = Evidence(
      id: evidenceId,
      observationId: observationId,
      type: type,
      role: role,
      originalPath: stored.originalPath,
      mimeType: stored.mimeType,
      sizeBytes: stored.sizeBytes,
      sha256: stored.sha256,
      capturedAt: captured,
      latitude: location?.latitude,
      longitude: location?.longitude,
      locationAccuracyMeters: location?.accuracyMeters,
      captureSource: captureSource,
      uploadState: SyncState.local,
    );

    QualityReport quality = QualityReport.analysisUnavailable();
    AnalysisResult analysisResult = AnalysisResult.unavailable(
      'Analysis not run.',
      VisualScreening.empty,
    );

    if (type == EvidenceType.image) {
      final Result<EvidenceIngest> imageOutcome = await _processImageEvidence(
        evidence: evidence,
        observationId: observationId,
        runAnalysis: runAnalysis,
        fallbackQuality: quality,
        fallbackAnalysis: analysisResult,
      );
      if (imageOutcome is Err<EvidenceIngest>) return imageOutcome;
      evidence = imageOutcome.value.evidence;
      quality = imageOutcome.value.quality;
      analysisResult = imageOutcome.value.analysis;
    } else {
      final Result<VideoEvidenceMeta> video = await pipeline.processVideo(
        sourcePath: stored.originalPath,
        measuredDuration: measuredVideoDuration,
      );
      if (video is Err<VideoEvidenceMeta>) {
        return Err<EvidenceIngest>(video.failure);
      }
      evidence = evidence.copyWith(
        durationMs: video.value.durationMs,
        uploadAttempts: 0,
      );
    }

    await database.saveEvidence(evidence);
    final Observation? observation = database.observationById(observationId);
    if (observation != null && !observation.evidenceIds.contains(evidenceId)) {
      await database.saveObservation(
        observation.copyWith(
          evidenceIds: <String>[...observation.evidenceIds, evidenceId],
          updatedAt: DateTime.now(),
        ),
      );
    }

    notifyListeners();
    return Ok<EvidenceIngest>(
      EvidenceIngest(
        evidence: evidence,
        quality: quality,
        analysis: analysisResult,
      ),
    );
  }

  Future<Result<EvidenceIngest>> _processImageEvidence({
    required Evidence evidence,
    required String observationId,
    required bool runAnalysis,
    required QualityReport fallbackQuality,
    required AnalysisResult fallbackAnalysis,
  }) async {
    final String observationDir =
        (await evidenceStore.observationDirectory(observationId)).path;
    final String evidenceId = evidence.id;

    final Result<ProcessedEvidence> processed = await pipeline.processImage(
      sourcePath: evidence.originalPath,
      uploadPath: '$observationDir/${evidenceId}_upload.jpg',
      aiPath: '$observationDir/${evidenceId}_ai.jpg',
      thumbnailPath: '$observationDir/${evidenceId}_thumb.jpg',
      aiMaxDimension: capabilities.aiMaxDimension,
      thumbnailMaxDimension: capabilities.thumbnailDimension,
      jpegQuality:
          capabilities.profile == PerformanceProfile.ultraLow ? 72 : 85,
    );

    if (processed is Err<ProcessedEvidence>) {
      AppLog.e('Repo', 'Image processing failed: ${processed.failure}');
      return Ok<EvidenceIngest>(
        EvidenceIngest(
          evidence: evidence,
          quality: fallbackQuality,
          analysis: fallbackAnalysis,
        ),
      );
    }

    final ProcessedEvidence result = processed.value;
    final Evidence updated = evidence.copyWith(
      width: result.width,
      height: result.height,
      uploadPath: result.uploadPath,
      aiPath: result.aiPath,
      thumbnailPath: result.thumbnailPath,
      perceptualHash: result.perceptualHash,
      uploadAttempts: 0,
    );

    AnalysisResult analysisResult = fallbackAnalysis;
    if (runAnalysis) {
      final Directory root = await evidenceStore.root();
      analysisResult = await analysis.analyze(
        imagePath: result.aiPath,
        workDirectory: root,
        screening: result.quality.screening,
      );
    }

    return Ok<EvidenceIngest>(
      EvidenceIngest(
        evidence: updated,
        quality: result.quality,
        analysis: analysisResult,
      ),
    );
  }
  /// Creates a new draft observation bound to a real location fix (§42).
  Future<Observation> createDraft({
    required LocationFix location,
    String category = 'other',
    String description = '',
  }) async {
    final DateTime now = DateTime.now();
    final SeverityAssessment severity =
        SeverityService.instance.assess(categoryId: category);
    final PriorityAssessment priority = PriorityService.instance.assess(
      severity: severity.level,
      severityScore: severity.score,
      categoryId: category,
    );
    final Observation draft = Observation(
      id: IdGenerator.observationId(now),
      clientId: IdGenerator.uuid(),
      createdAt: now,
      updatedAt: now,
      observerId: _observerId,
      category: category,
      description: description,
      severity: severity.level,
      severityScore: severity.score,
      priority: priority.level,
      priorityScore: priority.score,
      location: location,
      status: ObservationStatus.draft,
      syncState: SyncState.local,
    );
    await database.saveObservation(draft);
    notifyListeners();
    return draft;
  }

  /// Re-runs the assessment engines after the user changed the category or the
  /// analysis produced a suggestion (§38/§39/§41).
  Future<Observation> reassess({
    required Observation observation,
    required String category,
    double? aiConfidence,
    VisualScreening screening = VisualScreening.empty,
    bool categoryCorrectedByUser = false,
  }) async {
    final SeverityAssessment severity = SeverityService.instance.assess(
      categoryId: category,
      aiConfidence: aiConfidence,
      screening: screening,
      userConfirmedCategory: categoryCorrectedByUser,
    );
    final PriorityAssessment priority = PriorityService.instance.assess(
      severity: severity.level,
      severityScore: severity.score,
      categoryId: category,
      evidenceCount: observation.evidenceIds.length,
    );
    final Observation updated = observation.copyWith(
      category: category,
      aiConfidence: aiConfidence,
      aiSuggestedCategory:
          categoryCorrectedByUser ? observation.aiSuggestedCategory : category,
      categoryCorrectedByUser: categoryCorrectedByUser,
      severity: severity.level,
      severityScore: severity.score,
      priority: priority.level,
      priorityScore: priority.score,
      updatedAt: DateTime.now(),
    );
    await database.saveObservation(updated);
    notifyListeners();
    return updated;
  }

  /// Local advisory duplicate check (§40).
  DuplicateMatch? checkDuplicates(Observation observation) {
    final List<String> hashes = <String>[];
    for (final Evidence evidence
        in database.evidenceForObservation(observation.id)) {
      final String? hash = evidence.perceptualHash;
      if (hash != null && hash.isNotEmpty) hashes.add(hash);
    }
    return DuplicateService.instance.check(
      candidates: database.observations,
      categoryId: observation.category,
      location: observation.location,
      newHashes: hashes,
      ignoreObservationId: observation.id,
    );
  }

  /// Saves the observation locally and queues it for sync (§29).
  ///
  /// Local save always succeeds offline; the returned status reflects only
  /// what really happened — never a simulated "uploaded" state.
  Future<Result<Observation>> submit({
    required Observation observation,
    String? descriptionOverride,
  }) async {
    final int evidenceCount = observation.evidenceIds.length;
    if (evidenceCount == 0) {
      return const Err<Observation>(
        Failure('no_evidence', 'Add at least one photo or video first.'),
      );
    }

    Observation updated = observation.copyWith(
      description: descriptionOverride ?? observation.description,
      status: ObservationStatus.savedLocally,
      syncState: SyncState.queued,
      submittedAt: DateTime.now(),
      updatedAt: DateTime.now(),
      clearNextAttempt: true,
      clearLastError: true,
      attempts: 0,
      priorityScore: PriorityService.instance.assess(
        severity: observation.severity,
        severityScore: observation.severityScore,
        categoryId: observation.category,
        evidenceCount: evidenceCount,
      ).score,
    );
    updated = updated.copyWith(
      priority: PriorityLevel.fromScore(updated.priorityScore),
    );

    final Result<Observation> saved = await database.saveObservation(updated);
    if (saved is Err<Observation>) return saved;

    _lastSyncMessage = 'Saved locally — waiting for connection.';
    notifyListeners();

    if (network.backendReachable || client.isConfigured) {
      unawaited(syncNow());
    }
    return Ok<Observation>(updated);
  }
  // ---------------------------------------------------------------------------
  // Sync engine (§30/§31/§32/§33)
  // ---------------------------------------------------------------------------

  /// Exponential backoff with jitter, capped (never retries forever, §30).
  static Duration backoffFor(int attempts) {
    final int exponent = attempts.clamp(0, 10);
    Duration delay = MobileConfig.retryBaseDelay * (1 << exponent);
    if (delay > MobileConfig.retryMaxDelay) {
      delay = MobileConfig.retryMaxDelay;
    }
    final int jitterMs = (delay.inMilliseconds * 0.2).round();
    if (jitterMs <= 0) return delay;
    final int offset =
        (DateTime.now().microsecondsSinceEpoch % (jitterMs * 2)) - jitterMs;
    return delay + Duration(milliseconds: offset);
  }

  /// Runs one sync pass with bounded concurrency (§32).
  Future<void> syncNow() async {
    if (_syncRunning) return;

    if (!client.isConfigured) {
      _lastSyncMessage =
          'Backend not configured — reports are stored on this device.';
      notifyListeners();
      return;
    }

    _syncRunning = true;
    _lastSyncMessage = 'Checking connection…';
    notifyListeners();

    try {
      await network.refresh(baseUrl: _baseUrl);
      if (network.state != NetworkState.backendReachable) {
        _lastSyncMessage = network.state == NetworkState.offline
            ? 'Offline — reports stay saved on this device.'
            : 'Backend unreachable — will retry automatically.';
        notifyListeners();
        return;
      }

      final DateTime now = DateTime.now();
      final List<Observation> due = database
          .pendingSync()
          .where((Observation o) =>
              o.nextAttemptAt == null || !o.nextAttemptAt!.isAfter(now))
          .toList();

      if (due.isEmpty) {
        _lastSyncMessage = 'Everything is up to date.';
        notifyListeners();
        return;
      }

      final int concurrency = capabilities.uploadConcurrency.clamp(1, 3);
      int synced = 0;
      int failed = 0;
      for (int i = 0; i < due.length; i += concurrency) {
        final int end =
            i + concurrency > due.length ? due.length : i + concurrency;
        final List<bool> outcomes = await Future.wait(
          due.sublist(i, end).map((Observation o) => _syncOne(o)),
        );
        for (final bool ok in outcomes) {
          if (ok) {
            synced++;
          } else {
            failed++;
          }
        }
        _lastSyncMessage = 'Uploading $synced of ${due.length}…';
        notifyListeners();
      }

      _lastSyncMessage = failed == 0
          ? '$synced report(s) synced.'
          : '$synced synced, $failed waiting to retry.';
    } finally {
      _syncRunning = false;
      notifyListeners();
    }
  }
  /// Uploads one observation. Returns true only on a confirmed 2xx (§90).
  Future<bool> _syncOne(Observation observation) async {
    await database.saveObservation(
      observation.copyWith(
        syncState: SyncState.uploading,
        status: ObservationStatus.uploading,
        updatedAt: DateTime.now(),
      ),
    );
    notifyListeners();

    final Result<Map<String, dynamic>> created = await client.postJson(
      ApiEndpoints.observations,
      observation.toApiJson(),
      idempotencyKey: observation.clientId,
    );

    if (created is Err<Map<String, dynamic>>) {
      return _failSync(observation, created.failure);
    }

    final Map<String, dynamic> body = created.value;
    final String serverId = '${body['id'] ?? body['observationId'] ?? ''}';
    final String? caseId = body['caseId'] as String?;

    final List<Evidence> evidenceList =
        database.evidenceForObservation(observation.id)
          ..sort((Evidence a, Evidence b) {
            if (a.type == b.type) return 0;
            return a.type == EvidenceType.image ? -1 : 1;
          });

    for (final Evidence evidence in evidenceList) {
      final String uploadPath = evidence.uploadPath ?? evidence.originalPath;
      final File file = File(uploadPath);
      if (!await file.exists()) {
        await database.setEvidenceUploadState(
          evidence.id,
          SyncState.failed,
          error: 'File missing on device',
          attempts: evidence.uploadAttempts + 1,
        );
        continue;
      }

      await database.setEvidenceUploadState(evidence.id, SyncState.uploading);
      final Result<Map<String, dynamic>> uploaded =
          await client.uploadEvidence(
        path: evidence.isVideo ? ApiEndpoints.videos : ApiEndpoints.evidence,
        file: file,
        field: 'file',
        fields: <String, String>{
          'observationId':
              serverId.isNotEmpty ? serverId : observation.clientId,
          'clientId': observation.clientId,
          'evidenceId': evidence.id,
          'idempotencyKey': '${observation.clientId}-${evidence.id}',
          'sha256': evidence.sha256,
          'capturedAt': evidence.capturedAt.toIso8601String(),
          'role': evidence.role.name,
          'type': evidence.type.name,
        },
        onProgress: (double progress) {
          _uploadProgress = progress;
          notifyListeners();
        },
      );

      if (uploaded is Err<Map<String, dynamic>>) {
        await database.setEvidenceUploadState(
          evidence.id,
          SyncState.failed,
          error: uploaded.failure.message,
          attempts: evidence.uploadAttempts + 1,
        );
        return _failSync(observation, uploaded.failure);
      }

      await database.setEvidenceUploadState(
        evidence.id,
        SyncState.serverAccepted,
        serverId: '${uploaded.value['id'] ?? ''}',
        attempts: evidence.uploadAttempts + 1,
      );
    }

    await database.saveObservation(
      observation.copyWith(
        syncState: SyncState.synced,
        status: ObservationStatus.serverAccepted,
        serverId: serverId.isNotEmpty ? serverId : observation.serverId,
        caseId: caseId,
        attempts: 0,
        updatedAt: DateTime.now(),
        clearLastError: true,
        clearNextAttempt: true,
      ),
    );
    _lastSyncMessage = 'Report accepted by the server.';
    notifyListeners();
    return true;
  }

  /// Records a real failure and schedules a bounded retry (§30).
  Future<bool> _failSync(Observation observation, Failure failure) async {
    final bool transient = failure.code == 'network' ||
        failure.code == 'timeout' ||
        failure.code.startsWith('http_5');
    final int attempts = observation.attempts + 1;
    final bool exhausted = attempts >= MobileConfig.maxSyncAttempts;

    final SyncState state;
    if (!transient || exhausted) {
      state = SyncState.failed;
    } else {
      state = SyncState.retrying;
    }

    await database.saveObservation(
      observation.copyWith(
        syncState: state,
        status: ObservationStatus.pendingSync,
        attempts: attempts,
        nextAttemptAt: state == SyncState.retrying
            ? DateTime.now().add(backoffFor(attempts))
            : null,
        lastError: failure.message,
        updatedAt: DateTime.now(),
      ),
    );
    _lastSyncMessage = state == SyncState.failed
        ? 'Sync stopped: ${failure.message}'
        : 'Will retry automatically: ${failure.message}';
    AppLog.i(
      'Sync',
      '${observation.id} -> ${state.name} ($attempts): ${failure.code}',
    );
    notifyListeners();
    return false;
  }
  // ---------------------------------------------------------------------------
  // Read helpers used by the screens (§46/§48/§62)
  // ---------------------------------------------------------------------------

  Observation? observationById(String id) => database.observationById(id);
  List<Evidence> evidenceFor(String observationId) =>
      database.evidenceForObservation(observationId);

  Page<Observation> page({
    ReportFilter filter = ReportFilter.all,
    String search = '',
    int offset = 0,
    int limit = MobileConfig.reportsPageSize,
  }) =>
      database.pageObservations(
        filter: filter,
        search: search,
        offset: offset,
        limit: limit,
      );

  Map<ReportFilter, int> get filterCounts => database.filterCounts();
  List<Observation> get drafts => database.drafts;
  List<Observation> get all => database.observations;

  List<Observation> nearby(double lat, double lon, double radiusMeters) =>
      database.observationsWithinRadius(lat, lon, radiusMeters);

  List<Observation> inBounds({
    required double minLat,
    required double maxLat,
    required double minLon,
    required double maxLon,
  }) =>
      database.observationsInBounds(
        minLat: minLat,
        maxLat: maxLat,
        minLon: minLon,
        maxLon: maxLon,
      );

  /// Removes a draft (never a submitted report, §103).
  Future<Result<void>> discardDraft(String observationId) async {
    final Observation? observation = database.observationById(observationId);
    if (observation == null) {
      return const Err<void>(Failure('not_found', 'Report not found.'));
    }
    if (observation.isLocked) {
      return const Err<void>(
        Failure('record_locked', 'Submitted reports cannot be deleted.'),
      );
    }
    final Result<void> removed = await database.deleteObservation(observationId);
    if (removed is Ok<void>) {
      await evidenceStore.deleteObservationFiles(observationId);
    }
    notifyListeners();
    return removed;
  }

  /// Recomputes the pending count shown in the Sync Center.
  void refreshCounts() => notifyListeners();

  @override
  void dispose() {
    _client?.dispose();
    super.dispose();
  }
}