import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../core/app_logger.dart';
import '../core/query.dart';
import '../core/result.dart';
import '../models/evidence.dart';
import '../models/observation.dart';

/// Crash-safe, versioned local store for observations and evidence metadata.
///
/// Guarantees (§44, §45, §77):
/// - every write goes through a temp file + atomic replace, with the previous
///   revision kept as `.bak`;
/// - a schema version and explicit migrations are applied on open;
/// - a corrupt file is quarantined (never deleted) and the `.bak` is used;
/// - a store written by a *newer* schema is opened read-only so an app
///   downgrade can never destroy user data.
class LocalDatabase {
  LocalDatabase({required this.rootDirectory});

  final Directory rootDirectory;

  static const int schemaVersion = 2;

  final Map<String, Observation> _observations = <String, Observation>{};
  final Map<String, Evidence> _evidence = <String, Evidence>{};

  bool _isOpen = false;
  bool _isReadOnly = false;
  String? _openWarning;
  Future<void> _writeChain = Future<void>.value();

  bool get isOpen => _isOpen;

  /// True when the on-disk schema is newer than this build supports.
  bool get isReadOnly => _isReadOnly;

  /// Non-fatal problem detected while opening (shown once in Diagnostics).
  String? get openWarning => _openWarning;

  Directory get _dbDir => Directory('${rootDirectory.path}/db');
  File get _observationsFile => File('${_dbDir.path}/observations.json');
  File get _evidenceFile => File('${_dbDir.path}/evidence.json');
  File get _metaFile => File('${_dbDir.path}/meta.json');

  // ---------------------------------------------------------------------------
  // Open / load / migrate
  // ---------------------------------------------------------------------------
  Future<void> open() async {
    if (_isOpen) return;
    await _dbDir.create(recursive: true);

    final Map<String, dynamic> meta =
        await _readJsonObject(_metaFile) ?? <String, dynamic>{};
    final int storedVersion = (meta['schemaVersion'] as num?)?.toInt() ?? 0;

    if (storedVersion > schemaVersion) {
      _isReadOnly = true;
      _openWarning =
          'Local data was written by a newer app version (schema $storedVersion). '
          'Records are shown read-only to protect them.';
      AppLog.e('LocalDatabase', _openWarning!);
    }

    final List<dynamic> rawObservations = await _readList(_observationsFile, 'observations');
    final List<dynamic> rawEvidence = await _readList(_evidenceFile, 'evidence');

    for (final Object? entry in rawObservations) {
      final Map<String, dynamic> migrated = _migrateObservation(entry, storedVersion);
      final Observation? observation = Observation.fromJson(migrated);
      if (observation == null) {
        _openWarning ??= 'Some stored records could not be read and were skipped.';
        continue;
      }
      _observations[observation.id] = observation;
    }

    for (final Object? entry in rawEvidence) {
      final Evidence? evidence = Evidence.fromJson(_migrateEvidence(entry, storedVersion));
      if (evidence == null) continue;
      _evidence[evidence.id] = evidence;
    }

    _isOpen = true;
    AppLog.i(
      'LocalDatabase',
      'Opened store: ${_observations.length} observation(s), ${_evidence.length} evidence record(s), schema $schemaVersion',
    );

    if (storedVersion != schemaVersion && !_isReadOnly) {
      await _persistAll();
      await _writeJsonAtomic(_metaFile, <String, dynamic>{
        'schemaVersion': schemaVersion,
        'migratedFrom': storedVersion,
        'migratedAt': DateTime.now().toIso8601String(),
      });
    }
  }
  // ---------------------------------------------------------------------------
  // Low-level IO helpers
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>?> _readJsonObject(File file) async {
    try {
      if (!await file.exists()) return null;
      final Object? decoded = jsonDecode(await file.readAsString());
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (e) {
      AppLog.e('LocalDatabase', 'Could not read ${file.path}: $e');
      return null;
    }
  }

  /// Reads a list payload, falling back to the `.bak` revision, and quarantines
  /// (never deletes) a file that cannot be parsed at all.
  Future<List<dynamic>> _readList(File file, String key) async {
    for (final File candidate in <File>[file, File('${file.path}.bak')]) {
      try {
        if (!await candidate.exists()) continue;
        final Object? decoded = jsonDecode(await candidate.readAsString());
        if (decoded is Map && decoded[key] is List) {
          return decoded[key] as List<dynamic>;
        }
        if (decoded is List) return decoded;
      } catch (e) {
        AppLog.e('LocalDatabase', 'Unreadable store ${candidate.path}: $e');
      }
    }

    if (await file.exists()) {
      final String quarantine =
          '${file.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}';
      try {
        await file.rename(quarantine);
        _openWarning =
            'A stored data file was unreadable and has been quarantined instead of deleted.';
        AppLog.e('LocalDatabase', 'Quarantined unreadable file to $quarantine');
      } catch (e) {
        AppLog.e('LocalDatabase', 'Could not quarantine ${file.path}: $e');
      }
    }
    return <dynamic>[];
  }

  /// Atomic write: temp file -> fsync -> keep previous revision as `.bak` ->
  /// replace target.
  Future<void> _writeJsonAtomic(File target, Object payload) {
    if (_isReadOnly) {
      return Future<void>.error(
        StateError('Local store is read-only (newer schema on disk).'),
      );
    }
    _writeChain = _writeChain.then((_) async {
      try {
        final File tmp = File('${target.path}.tmp');
        final File bak = File('${target.path}.bak');
        await tmp.writeAsString(jsonEncode(payload), flush: true);
        if (await target.exists()) {
          await target.copy(bak.path);
        }
        await tmp.rename(target.path);
      } catch (e) {
        AppLog.e('LocalDatabase', 'Write failed for ${target.path}: $e');
      }
    });
    return _writeChain;
  }

  Future<void> _persistObservations() => _writeJsonAtomic(
        _observationsFile,
        <String, dynamic>{
          'schemaVersion': schemaVersion,
          'savedAt': DateTime.now().toIso8601String(),
          'observations': _observations.values
              .map((Observation o) => o.toJson())
              .toList(growable: false),
        },
      );

  Future<void> _persistEvidence() => _writeJsonAtomic(
        _evidenceFile,
        <String, dynamic>{
          'schemaVersion': schemaVersion,
          'savedAt': DateTime.now().toIso8601String(),
          'evidence': _evidence.values
              .map((Evidence e) => e.toJson())
              .toList(growable: false),
        },
      );

  Future<void> _persistAll() async {
    await _persistObservations();
    await _persistEvidence();
  }

  /// Flush pending writes (called when the app goes to the background).
  Future<void> flush() => _writeChain;

  // ---------------------------------------------------------------------------
  // Migrations (§44, §77)
  // ---------------------------------------------------------------------------
  Map<String, dynamic> _migrateObservation(Object? entry, int fromVersion) {
    if (entry is! Map) return <String, dynamic>{};
    final Map<String, dynamic> json = Map<String, dynamic>.from(entry);

    // v0/v1 stored flat latitude/longitude fields and no nested location.
    if (json['location'] is! Map) {
      final Object? lat = json['latitude'];
      final Object? lon = json['longitude'];
      if (lat is num && lon is num) {
        json['location'] = <String, dynamic>{
          'latitude': lat.toDouble(),
          'longitude': lon.toDouble(),
          'accuracyMeters': (json['locationAccuracy'] as num?)?.toDouble() ?? -1,
          'timestamp': json['locationTimestamp'] ?? json['createdAt'],
          'isMocked': false,
          'isApproximatePermission': false,
        };
      }
    }
    if (json['evidenceIds'] == null && json['evidencePaths'] is List) {
      json['evidenceIds'] = <String>[];
    }
    json['schemaVersion'] = schemaVersion;
    if (fromVersion < schemaVersion) {
      json['updatedAt'] ??= json['createdAt'];
    }
    return json;
  }

  Map<String, dynamic> _migrateEvidence(Object? entry, int fromVersion) {
    if (entry is! Map) return <String, dynamic>{};
    final Map<String, dynamic> json = Map<String, dynamic>.from(entry);
    json['sha256'] ??= '';
    json['mimeType'] ??= 'application/octet-stream';
    json['captureSource'] ??= 'legacy';
    return json;
  }
  // ---------------------------------------------------------------------------
  // Observation CRUD
  // ---------------------------------------------------------------------------
  List<Observation> get observations {
    final List<Observation> list = _observations.values.toList(growable: false);
    list.sort((Observation a, Observation b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Observation? observationById(String id) => _observations[id];

  Future<Result<Observation>> saveObservation(Observation observation) async {
    if (_isReadOnly) {
      return const Err<Observation>(
        Failure('store_read_only', 'Local storage is read-only right now.'),
      );
    }
    _observations[observation.id] = observation;
    await _persistObservations();
    return Ok<Observation>(observation);
  }

  Future<void> saveAll(List<Observation> records) async {
    for (final Observation observation in records) {
      _observations[observation.id] = observation;
    }
    await _persistObservations();
  }

  /// Deleting a submitted observation is never allowed (§103): the local
  /// record must stay in sync with whatever the backend already accepted.
  Future<Result<void>> deleteObservation(String id) async {
    final Observation? existing = _observations[id];
    if (existing == null) {
      return const Err<void>(Failure('not_found', 'Observation not found.'));
    }
    if (existing.isLocked) {
      return const Err<void>(
        Failure(
          'record_locked',
          'Submitted observations cannot be deleted on the device.',
        ),
      );
    }
    _observations.remove(id);
    final List<String> evidenceIds = _evidence.values
        .where((Evidence e) => e.observationId == id)
        .map((Evidence e) => e.id)
        .toList(growable: false);
    for (final String evidenceId in evidenceIds) {
      _evidence.remove(evidenceId);
    }
    await _persistAll();
    return const Ok<void>(null);
  }

  // ---------------------------------------------------------------------------
  // Evidence CRUD
  // ---------------------------------------------------------------------------
  Future<Result<Evidence>> saveEvidence(Evidence evidence) async {
    if (_isReadOnly) {
      return const Err<Evidence>(
        Failure('store_read_only', 'Local storage is read-only right now.'),
      );
    }
    _evidence[evidence.id] = evidence;
    await _persistEvidence();
    return Ok<Evidence>(evidence);
  }

  Evidence? evidenceById(String id) => _evidence[id];

  List<Evidence> evidenceForObservation(String observationId) {
    final List<Evidence> list = _evidence.values
        .where((Evidence e) => e.observationId == observationId)
        .toList(growable: false);
    list.sort((Evidence a, Evidence b) => a.capturedAt.compareTo(b.capturedAt));
    return list;
  }
  /// User-driven evidence edits (role / removal) respect record immutability.
  Future<Result<Evidence>> updateEvidenceFields(
    String evidenceId, {
    EvidenceRole? role,
    bool remove = false,
  }) async {
    final Evidence? existing = _evidence[evidenceId];
    if (existing == null) {
      return const Err<Evidence>(Failure('not_found', 'Evidence not found.'));
    }
    final Observation? parent = _observations[existing.observationId];
    if (parent != null && parent.isLocked) {
      return const Err<Evidence>(
        Failure(
          'record_locked',
          'Evidence is locked because the report was already submitted.',
        ),
      );
    }
    if (remove) {
      _evidence.remove(evidenceId);
      await _persistEvidence();
      return Ok<Evidence>(existing);
    }
    final Evidence updated = existing.copyWith(role: role);
    _evidence[evidenceId] = updated;
    await _persistEvidence();
    return Ok<Evidence>(updated);
  }

  /// System update used by the sync engine (allowed on locked records).
  Future<void> setEvidenceUploadState(
    String evidenceId,
    SyncState state, {
    String? serverId,
    String? error,
    int? attempts,
  }) async {
    final Evidence? existing = _evidence[evidenceId];
    if (existing == null) return;
    _evidence[evidenceId] = existing.copyWith(
      uploadState: state,
      serverId: serverId,
      uploadAttempts: attempts,
      lastError: error,
      clearLastError: error == null,
    );
    await _persistEvidence();
  }

  int get totalEvidenceCount => _evidence.length;
  // ---------------------------------------------------------------------------
  // Queries used by the UI (§46, §48, §49)
  // ---------------------------------------------------------------------------
  int countWhere(bool Function(Observation) test) =>
      _observations.values.where(test).length;

  Map<ReportFilter, int> filterCounts() => <ReportFilter, int>{
        for (final ReportFilter filter in ReportFilter.values)
          filter: countWhere(filter.matches),
      };

  Page<Observation> pageObservations({
    ReportFilter filter = ReportFilter.all,
    String search = '',
    int offset = 0,
    int limit = 20,
  }) {
    final String needle = search.trim().toLowerCase();
    final List<Observation> filtered = observations.where((Observation o) {
      if (!filter.matches(o)) return false;
      if (needle.isEmpty) return true;
      return o.id.toLowerCase().contains(needle) ||
          o.category.toLowerCase().contains(needle) ||
          o.description.toLowerCase().contains(needle) ||
          (o.caseId ?? '').toLowerCase().contains(needle);
    }).toList(growable: false);

    final int start = offset.clamp(0, filtered.length);
    final int end = (start + limit).clamp(0, filtered.length);
    return Page<Observation>(
      items: filtered.sublist(start, end),
      total: filtered.length,
      offset: start,
      limit: limit,
    );
  }

  /// Observations inside a map viewport, capped so the app never renders an
  /// unbounded marker set (§48/§63).
  List<Observation> observationsInBounds({
    required double minLat,
    required double maxLat,
    required double minLon,
    required double maxLon,
    int limit = 300,
  }) {
    final List<Observation> matches = <Observation>[];
    for (final Observation o in observations) {
      final double lat = o.location.latitude;
      final double lon = o.location.longitude;
      if (lat < minLat || lat > maxLat || lon < minLon || lon > maxLon) continue;
      matches.add(o);
      if (matches.length >= limit) break;
    }
    return matches;
  }

  List<Observation> observationsWithinRadius(
    double latitude,
    double longitude,
    double radiusMeters, {
    int limit = 200,
  }) {
    final List<Observation> matches = <Observation>[];
    for (final Observation o in observations) {
      if (haversineMeters(
            latitude,
            longitude,
            o.location.latitude,
            o.location.longitude,
          ) <=
          radiusMeters) {
        matches.add(o);
        if (matches.length >= limit) break;
      }
    }
    return matches;
  }

  List<Observation> pendingSync({int limit = 500}) => _observations.values
      .where((Observation o) =>
          o.syncState.isPending || o.status == ObservationStatus.pendingSync)
      .take(limit)
      .toList(growable: false);

  List<Observation> get drafts => _observations.values
      .where((Observation o) => o.status == ObservationStatus.draft)
      .toList(growable: false);

  Map<String, int> countByCategory() {
    final Map<String, int> counts = <String, int>{};
    for (final Observation o in _observations.values) {
      counts[o.category] = (counts[o.category] ?? 0) + 1;
    }
    return counts;
  }

  /// Great-circle distance in metres — used by duplicate detection (§40) and
  /// the Nearby list. Uses `dart:math` so it is correct and isolate-safe.
  static double haversineMeters(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000.0;
    final double dLat = _degToRad(lat2 - lat1);
    final double dLon = _degToRad(lon2 - lon1);
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _degToRad(double degrees) => degrees * math.pi / 180.0;

  Future<void> close() async {
    await flush();
    _observations.clear();
    _evidence.clear();
    _isOpen = false;
  }
}
