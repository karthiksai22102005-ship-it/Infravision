import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../core/app_logger.dart';
import '../models/evidence.dart';

/// Outcome of importing an original capture into the immutable evidence vault.
class StoredCapture {
  const StoredCapture({
    required this.originalPath,
    required this.sha256,
    required this.sizeBytes,
    required this.mimeType,
    required this.extension,
    required this.wasReused,
  });

  final String originalPath;
  final String sha256;
  final int sizeBytes;
  final String mimeType;
  final String extension;

  /// True when a file with the same SHA-256 already existed — this is how the
  /// store prevents storing the same capture twice (§33).
  final bool wasReused;
}

class StorageBreakdown {
  const StorageBreakdown({
    required this.originalBytes,
    required this.derivativeBytes,
    required this.databaseBytes,
    required this.modelBytes,
    required this.totalBytes,
    required this.fileCount,
  });

  final int originalBytes;
  final int derivativeBytes;
  final int databaseBytes;
  final int modelBytes;
  final int totalBytes;
  final int fileCount;

  static const StorageBreakdown empty = StorageBreakdown(
    originalBytes: 0,
    derivativeBytes: 0,
    databaseBytes: 0,
    modelBytes: 0,
    totalBytes: 0,
    fileCount: 0,
  );
}

/// Immutable on-disk evidence vault (§13, §43, §60).
///
/// Layout: `<documents>/infravision_observation/evidence/<observationId>/…`
/// - `*_orig.*`      untouched original capture (never re-encoded)
/// - `*_upload.jpg`  compressed derivative used for uploads
/// - `*_ai.jpg`      downscaled derivative for analysis
/// - `*_thumb.jpg`   bounded thumbnail for lists (regenerable)
///
/// The app documents directory (not the cache directory) is used on purpose:
/// Android may purge cache files at any time, which would destroy evidence.
class EvidenceStore {
  EvidenceStore({Directory? rootDirectory}) : _rootDirectory = rootDirectory;

  Directory? _rootDirectory;

  /// Test hook: allows injecting a temp directory without plugins.
  static Directory? rootDirectoryOverride;

  Future<Directory> _resolveRoot() async {
    final Directory? override = rootDirectoryOverride;
    if (override != null) {
      return override;
    }
    if (_rootDirectory != null) return _rootDirectory!;
    Directory base;
    try {
      base = await getApplicationDocumentsDirectory();
    } catch (e) {
      // Platform channel unavailable (tests / rare OEM failures): fall back to
      // a temp directory rather than crashing, and record the fact.
      AppLog.e('EvidenceStore', 'path_provider unavailable, using temp dir: $e');
      base = Directory.systemTemp;
    }
    _rootDirectory = Directory('${base.path}/infravision_observation');
    return _rootDirectory!;
  }

  Future<Directory> root() async => (await _resolveRoot());

  Future<Directory> databaseDirectory() async =>
      Directory('${(await _resolveRoot()).path}/db');
  Future<Directory> observationDirectory(String observationId) async {
    final Directory dir = Directory(
      '${(await _resolveRoot()).path}/evidence/$observationId',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<String> originalPathFor(
    String observationId,
    String evidenceId,
    String ext,
  ) async {
    final Directory dir = await observationDirectory(observationId);
    return '${dir.path}/${evidenceId}_orig.$ext';
  }

  Future<String> derivativePathFor(
    String observationId,
    String evidenceId,
    String kind,
    String ext,
  ) async {
    final Directory dir = await observationDirectory(observationId);
    return '${dir.path}/${evidenceId}_$kind.$ext';
  }

  /// Copies an incoming file into the vault and computes its SHA-256 with a
  /// stream — the full file is never loaded into memory (§14/§55).
  Future<StoredCapture> importOriginal({
    required String observationId,
    required String evidenceId,
    required File source,
    required EvidenceType type,
    required String extension,
    String mimeType = 'image/jpeg',
  }) async {
    final Directory dir = await observationDirectory(observationId);
    final String ext = extension.toLowerCase().replaceAll('.', '');
    final String targetPath = '${dir.path}/${evidenceId}_orig.$ext';

    final File temporary = File('$targetPath.part');
    await source.copy(temporary.path);

    final int size = await temporary.length();
    if (size <= 0) {
      await temporary.delete();
      throw FileSystemException('Captured file is empty', targetPath);
    }

    final Digest digest = await sha256.bind(temporary.openRead()).first;

    // Content-addressed de-duplication: if identical bytes already exist for
    // this observation, reuse them instead of storing a second copy.
    String existingPath = '';
    await for (final FileSystemEntity entity
        in dir.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('_orig.$ext')) continue;
      if (entity.path == targetPath) continue;
      final String otherHash =
          (await sha256.bind(entity.openRead()).first).toString();
      if (otherHash == digest.toString()) {
        existingPath = entity.path;
        break;
      }
    }

    if (existingPath.isNotEmpty) {
      await temporary.delete();
      return StoredCapture(
        originalPath: existingPath,
        sha256: digest.toString(),
        sizeBytes: size,
        mimeType: mimeType,
        extension: ext,
        wasReused: true,
      );
    }

    await temporary.rename(targetPath);
    return StoredCapture(
      originalPath: targetPath,
      sha256: digest.toString(),
      sizeBytes: size,
      mimeType: mimeType,
      extension: ext,
      wasReused: false,
    );
  }

  /// Verifies an evidence file still matches its recorded SHA-256 (§73).
  Future<bool> verifyIntegrity(String path, String expectedSha256) async {
    try {
      final File file = File(path);
      if (!await file.exists()) return false;
      final Digest digest = await sha256.bind(file.openRead()).first;
      return digest.toString() == expectedSha256;
    } catch (e) {
      AppLog.e('EvidenceStore', 'Integrity check failed for $path: $e');
      return false;
    }
  }
  /// Measured storage usage broken down by what may and may not be deleted.
  Future<StorageBreakdown> usage() async {
    final Directory rootDir = await _resolveRoot();
    if (!await rootDir.exists()) return StorageBreakdown.empty;

    int originalBytes = 0;
    int derivativeBytes = 0;
    int databaseBytes = 0;
    int modelBytes = 0;
    int fileCount = 0;

    await for (final FileSystemEntity entity
        in rootDir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      fileCount++;
      final int size = await entity.length();
      final String path = entity.path;
      if (path.contains('/evidence/') &&
          path.contains('_orig.')) {
        originalBytes += size;
      } else if (path.contains('/models/')) {
        modelBytes += size;
      } else if (path.contains('/db/') || path.endsWith('.json')) {
        databaseBytes += size;
      } else {
        derivativeBytes += size;
      }
    }

    return StorageBreakdown(
      originalBytes: originalBytes,
      derivativeBytes: derivativeBytes,
      databaseBytes: databaseBytes,
      modelBytes: modelBytes,
      totalBytes: originalBytes + derivativeBytes + databaseBytes + modelBytes,
      fileCount: fileCount,
    );
  }

  /// Removes only *regenerable* derivatives (thumbnails, analysis and upload
  /// copies) plus stray temp files. Original evidence, evidence metadata and
  /// pending sync records are never touched (§60).
  Future<int> clearRegenerableDerivatives() async {
    final Directory rootDir = await _resolveRoot();
    if (!await rootDir.exists()) return 0;
    int freed = 0;
    await for (final FileSystemEntity entity
        in rootDir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final String name = entity.uri.pathSegments.last;
      final bool regenerable = name.endsWith('_thumb.jpg') ||
          name.endsWith('_ai.jpg') ||
          name.endsWith('_upload.jpg') ||
          name.endsWith('.part') ||
          name.endsWith('.tmp') ||
          name.contains('.corrupt-');
      if (!regenerable) continue;
      try {
        freed += await entity.length();
        await entity.delete();
      } catch (e) {
        AppLog.e('EvidenceStore', 'Could not delete ${entity.path}: $e');
      }
    }
    AppLog.i('EvidenceStore', 'Cleared $freed bytes of regenerable data');
    return freed;
  }

  /// Deletes every file belonging to one observation — only ever called for
  /// unsubmitted drafts (the caller verifies `Observation.isLocked`).
  Future<void> deleteObservationFiles(String observationId) async {
    try {
      final Directory dir = Directory(
        '${(await _resolveRoot()).path}/evidence/$observationId',
      );
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e) {
      AppLog.e('EvidenceStore', 'Could not delete evidence for $observationId: $e');
    }
  }

  /// Best-effort full-volume probe: writes and deletes a small file so the UI
  /// can tell whether the volume is genuinely full (§60). This detects an
  /// exhausted disk; it does NOT report the amount of free space (which is not
  /// readable from Dart without a platform channel).
  Future<bool> probeStorageWritable() async {
    try {
      final Directory rootDir = await _resolveRoot();
      final File probe = File('${rootDir.path}/.space_probe');
      await probe.writeAsBytes(List<int>.filled(64 * 1024, 0), flush: true);
      final int size = await probe.length();
      await probe.delete();
      return size == 64 * 1024;
    } catch (_) {
      return false;
    }
  }

  Future<void> close() async {
    _rootDirectory = null;
  }
}