import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:infravision/mobile/config/mobile_config.dart';
import 'package:infravision/mobile/core/query.dart';
import 'package:infravision/mobile/core/result.dart';
import 'package:infravision/mobile/data/evidence_store.dart';
import 'package:infravision/mobile/data/local_database.dart';
import 'package:infravision/mobile/models/analysis.dart';
import 'package:infravision/mobile/models/evidence.dart';
import 'package:infravision/mobile/models/observation.dart';
import 'package:infravision/mobile/repositories/observation_repository.dart';
import 'package:infravision/mobile/services/analysis_service.dart';
import 'package:infravision/mobile/services/device_capability_service.dart';
import 'package:infravision/mobile/services/image_pipeline_service.dart';
import 'package:infravision/mobile/services/network_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Offline behaviour of the Observation Repository: local-first writes, the
/// quality pipeline, honest sync state and duplicate protection (§29-§40).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory vaultRoot;
  late Directory captureDir;
  late LocalDatabase database;
  late ObservationRepository repository;

  LocationFix fixAt(double lat, double lon) => LocationFix(
        latitude: lat,
        longitude: lon,
        accuracyMeters: 6,
        timestamp: DateTime.now(),
      );

  /// A synthetic but structurally valid JPEG (real bytes, real dimensions).
  File writeJpeg(
    String name, {
    int width = 480,
    int height = 360,
    int seed = 0,
  }) {
    final img.Image image = img.Image(width: width, height: height);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        image.setPixelRgb(
          x,
          y,
          (x * 3 + y + seed) % 256,
          (x + y * 2 + seed * 7) % 256,
          (x * 5 + y * 3 + seed * 11) % 256,
        );
      }
    }
    final Uint8List bytes = img.encodeJpg(image, quality: 90);
    final File file = File('${captureDir.path}/$name');
    file.writeAsBytesSync(bytes);
    return file;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    vaultRoot = await Directory.systemTemp.createTemp('obs_vault');
    captureDir = await Directory.systemTemp.createTemp('obs_capture');
    EvidenceStore.rootDirectoryOverride = vaultRoot;

    final DeviceCapabilityService capabilities = DeviceCapabilityService();
    await capabilities.initialize();

    database = LocalDatabase(rootDirectory: vaultRoot);
    repository = ObservationRepository(
      database: database,
      evidenceStore: EvidenceStore(rootDirectory: vaultRoot),
      network: NetworkService(),
      capabilities: capabilities,
      analysis: AnalysisService(),
      pipeline: ImagePipelineService.instance,
    );
    await repository.initialize();
  });

  tearDown(() async {
    repository.dispose();
    EvidenceStore.rootDirectoryOverride = null;
    for (final Directory dir in <Directory>[vaultRoot, captureDir]) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {
        // Already removed by the OS — nothing left to clean up.
      }
    }
  });

  test('a draft is stored locally with computed severity and priority',
      () async {
    final Observation draft = await repository.createDraft(
      location: fixAt(12.9716, 77.5946),
      category: 'pothole',
      description: 'Deep crater near the bus stop',
    );

    expect(draft.status, ObservationStatus.draft);
    expect(draft.syncState, SyncState.local);
    expect(draft.severityScore, greaterThan(0));
    expect(draft.priorityScore, greaterThan(0));
    expect(draft.clientId, isNotEmpty);
    expect(database.observationById(draft.id), isNotNull);
    expect(repository.drafts.map((Observation o) => o.id), contains(draft.id));
  });

  test('a valid photo becomes evidence with hash, derivatives and quality',
      () async {
    final Observation draft = await repository.createDraft(
      location: fixAt(12.9716, 77.5946),
      category: 'pothole',
    );
    final File photo = writeJpeg('street.jpg', seed: 3);

    final Result<EvidenceIngest> result = await repository.ingestEvidence(
      observationId: draft.id,
      file: photo,
      type: EvidenceType.image,
      location: fixAt(12.9716, 77.5946),
    );

    expect(result, isA<Ok<EvidenceIngest>>());
    final EvidenceIngest ingest = result.value;
    expect(ingest.evidence.sha256.length, 64);
    expect(ingest.evidence.width, 480);
    expect(ingest.evidence.height, 360);
    expect(ingest.evidence.sizeBytes, greaterThan(0));
    expect(File(ingest.evidence.originalPath).existsSync(), isTrue);
    expect(ingest.quality.grade, isNot(QualityGrade.unavailable));
    expect(
      database.observationById(draft.id)!.evidenceIds,
      contains(ingest.evidence.id),
    );
  });

  test('a file whose bytes are not an image is rejected before storage',
      () async {
    final Observation draft = await repository.createDraft(
      location: fixAt(12.9716, 77.5946),
      category: 'pothole',
    );
    final File fake = File('${captureDir.path}/fake.jpg')
      ..writeAsBytesSync(List<int>.filled(4096, 0x41));

    final Result<EvidenceIngest> result = await repository.ingestEvidence(
      observationId: draft.id,
      file: fake,
      type: EvidenceType.image,
    );

    expect(result, isA<Err<EvidenceIngest>>());
    expect(result.failure.code, isNotEmpty);
    expect(
      database.evidenceForObservation(draft.id),
      isEmpty,
      reason: 'a rejected file must never be recorded as evidence',
    );
  });

  test('submit needs evidence, then queues the report locally only', () async {
    final Observation draft = await repository.createDraft(
      location: fixAt(12.9716, 77.5946),
      category: 'pothole',
    );
    final Result<Observation> rejected =
        await repository.submit(observation: draft);
    expect(rejected, isA<Err<Observation>>());
    expect(rejected.failure.code, 'no_evidence');

    await repository.ingestEvidence(
      observationId: draft.id,
      file: writeJpeg('road.jpg', seed: 9),
      type: EvidenceType.image,
    );
    final Result<Observation> accepted = await repository.submit(
      observation: database.observationById(draft.id)!,
      descriptionOverride: 'Submitted after capture',
    );

    expect(accepted, isA<Ok<Observation>>());
    final Observation saved = accepted.value;
    expect(saved.status, ObservationStatus.savedLocally);
    expect(saved.syncState, SyncState.queued);
    expect(saved.serverId, isNull, reason: 'nothing was really uploaded');
    expect(saved.description, 'Submitted after capture');
    expect(repository.pendingCount, 1);
  });

  test('sync without a backend says so and keeps the report queued', () async {
    final Observation draft = await repository.createDraft(
      location: fixAt(12.9716, 77.5946),
      category: 'drainage_issue',
    );
    await repository.ingestEvidence(
      observationId: draft.id,
      file: writeJpeg('drain.jpg', seed: 4),
      type: EvidenceType.image,
    );
    await repository.submit(observation: database.observationById(draft.id)!);

    await repository.syncNow();
    expect(repository.pendingCount, 1);
    expect(repository.lastSyncMessage, contains('Backend not configured'));

    await repository.setBackendUrl('https://backend.invalid');
    await repository.syncNow();
    final Observation stored = database.observationById(draft.id)!;
    expect(
      stored.syncState,
      isNot(SyncState.synced),
      reason: 'an unreachable backend must never be reported as synced',
    );
    expect(repository.pendingCount, 1);
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('backoff grows with attempts and stays capped', () {
    final Duration first = ObservationRepository.backoffFor(0);
    final Duration later = ObservationRepository.backoffFor(4);
    final Duration capped = ObservationRepository.backoffFor(12);

    expect(first.inSeconds, greaterThan(0));
    expect(later, greaterThan(first));
    expect(
      capped,
      lessThanOrEqualTo(
        MobileConfig.retryMaxDelay + MobileConfig.retryMaxDelay,
      ),
    );
  });

  test('drafts can be discarded, accepted reports cannot', () async {
    final Observation draft = await repository.createDraft(
      location: fixAt(12.9716, 77.5946),
      category: 'obstruction',
    );
    final Result<EvidenceIngest> ingested = await repository.ingestEvidence(
      observationId: draft.id,
      file: writeJpeg('debris.jpg', seed: 5),
      type: EvidenceType.image,
    );
    final String originalPath =
        (ingested as Ok<EvidenceIngest>).value.evidence.originalPath;

    final Result<void> discarded = await repository.discardDraft(draft.id);
    expect(discarded, isA<Ok<void>>());
    expect(database.observationById(draft.id), isNull);
    expect(File(originalPath).existsSync(), isFalse,
        reason: 'discarding a draft must also remove its evidence files');

    final Observation accepted = await repository.createDraft(
      location: fixAt(12.9716, 77.5946),
      category: 'obstruction',
    );
    await repository.ingestEvidence(
      observationId: accepted.id,
      file: writeJpeg('debris2.jpg', seed: 6),
      type: EvidenceType.image,
    );
    await repository.submit(observation: database.observationById(accepted.id)!);

    // Once the backend has a record the report becomes immutable (§15/§103).
    await database.saveObservation(
      database.observationById(accepted.id)!.copyWith(
        status: ObservationStatus.serverAccepted,
        syncState: SyncState.synced,
        serverId: 'srv-1',
        caseId: 'CASE-1',
      ),
    );

    final Result<void> refused = await repository.discardDraft(accepted.id);
    expect(refused, isA<Err<void>>());
    expect(refused.failure.code, 'record_locked');
    expect(database.observationById(accepted.id), isNotNull);
  });

  test('a nearby recent report is flagged as a possible duplicate', () async {
    final LocationFix place = fixAt(12.9716, 77.5946);
    final Observation first = await repository.createDraft(
      location: place,
      category: 'pothole',
    );
    await repository.ingestEvidence(
      observationId: first.id,
      file: writeJpeg('first.jpg', seed: 12),
      type: EvidenceType.image,
    );
    await repository.submit(observation: database.observationById(first.id)!);

    final Observation second = await repository.createDraft(
      location: place,
      category: 'pothole',
    );

    final DuplicateMatch? match = repository.checkDuplicates(second);
    expect(match, isNotNull);
    expect(match!.observationId, first.id);
    expect(match.distanceMeters, lessThan(MobileConfig.duplicateRadiusMeters));
    expect(match.summary, contains('pothole'));
  });

  test('paging and filter counts describe the same local data', () async {
    for (int i = 0; i < 3; i++) {
      await repository.createDraft(
        location: fixAt(12.9716 + i * 0.01, 77.5946),
        category: 'pothole',
        description: 'Report $i',
      );
    }

    final Page<Observation> page = database.pageObservations(limit: 2);
    expect(page.items.length, 2);
    expect(page.total, 3);
    expect(page.hasMore, isTrue);
    expect(repository.filterCounts[ReportFilter.all], 3);
    // A draft is still local work, so it counts as "pending sync" too.
    expect(repository.filterCounts[ReportFilter.pendingSync], 3);
  });
}
