import 'observation.dart';

/// Kind of captured evidence.
enum EvidenceType {
  image('Image'),
  video('Video');

  const EvidenceType(this.label);
  final String label;

  static EvidenceType fromName(Object? name) =>
      name == 'video' ? EvidenceType.video : EvidenceType.image;
}

/// Semantic role of an evidence item inside one observation (§15).
enum EvidenceRole {
  front('Front view'),
  closeUp('Close-up'),
  side('Side view'),
  context('Context view'),
  additional('Additional evidence');

  const EvidenceRole(this.label);
  final String label;

  static EvidenceRole fromName(Object? name) {
    for (final EvidenceRole v in EvidenceRole.values) {
      if (v.name == name) return v;
    }
    return EvidenceRole.additional;
  }
}

/// One immutable evidence artifact attached to an observation (§43).
///
/// The original file is never overwritten or re-encoded: derivatives
/// (`uploadPath`, `aiPath`, `thumbnailPath`) are separate files.
class Evidence {
  const Evidence({
    required this.id,
    required this.observationId,
    required this.type,
    required this.originalPath,
    required this.mimeType,
    required this.sizeBytes,
    required this.sha256,
    required this.capturedAt,
    this.role = EvidenceRole.additional,
    this.uploadPath,
    this.aiPath,
    this.thumbnailPath,
    this.width,
    this.height,
    this.durationMs,
    this.perceptualHash,
    this.latitude,
    this.longitude,
    this.locationAccuracyMeters,
    this.uploadState = SyncState.local,
    this.serverId,
    this.captureSource = 'device-camera',
    this.uploadAttempts = 0,
    this.lastError,
  });

  final String id;
  final String observationId;
  final EvidenceType type;
  final EvidenceRole role;

  /// Absolute path of the untouched original capture.
  final String originalPath;

  /// Compressed derivative that is uploaded (never replaces the original).
  final String? uploadPath;

  /// Downscaled derivative used for on-device analysis.
  final String? aiPath;

  /// Small derivative used by list/gallery UIs (bounded memory, §55).
  final String? thumbnailPath;

  final String mimeType;
  final int sizeBytes;
  final int? width;
  final int? height;
  final int? durationMs;

  /// SHA-256 of the original bytes — evidence integrity (§73).
  final String sha256;

  /// 64-bit dHash of the thumbnail, used for advisory duplicate checks (§40).
  final String? perceptualHash;

  final DateTime capturedAt;
  final double? latitude;
  final double? longitude;
  final double? locationAccuracyMeters;

  final SyncState uploadState;
  final String? serverId;

  /// camera | gallery | files — provenance is recorded, never assumed.
  final String captureSource;
  final int uploadAttempts;
  final String? lastError;

  bool get isVideo => type == EvidenceType.video;

  /// Path that should be rendered in bounded-memory list UIs.
  String get listImagePath => thumbnailPath ?? uploadPath ?? originalPath;
  Evidence copyWith({
    EvidenceRole? role,
    String? uploadPath,
    String? aiPath,
    String? thumbnailPath,
    int? width,
    int? height,
    int? durationMs,
    String? perceptualHash,
    double? latitude,
    double? longitude,
    double? locationAccuracyMeters,
    SyncState? uploadState,
    String? serverId,
    int? uploadAttempts,
    String? lastError,
    bool clearLastError = false,
  }) {
    return Evidence(
      id: id,
      observationId: observationId,
      type: type,
      role: role ?? this.role,
      originalPath: originalPath,
      uploadPath: uploadPath ?? this.uploadPath,
      aiPath: aiPath ?? this.aiPath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      width: width ?? this.width,
      height: height ?? this.height,
      durationMs: durationMs ?? this.durationMs,
      sha256: sha256,
      perceptualHash: perceptualHash ?? this.perceptualHash,
      capturedAt: capturedAt,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationAccuracyMeters:
          locationAccuracyMeters ?? this.locationAccuracyMeters,
      uploadState: uploadState ?? this.uploadState,
      serverId: serverId ?? this.serverId,
      captureSource: captureSource,
      uploadAttempts: uploadAttempts ?? this.uploadAttempts,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'observationId': observationId,
        'type': type.name,
        'role': role.name,
        'originalPath': originalPath,
        'uploadPath': uploadPath,
        'aiPath': aiPath,
        'thumbnailPath': thumbnailPath,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
        'width': width,
        'height': height,
        'durationMs': durationMs,
        'sha256': sha256,
        'perceptualHash': perceptualHash,
        'capturedAt': capturedAt.toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
        'locationAccuracyMeters': locationAccuracyMeters,
        'uploadState': uploadState.name,
        'serverId': serverId,
        'captureSource': captureSource,
        'uploadAttempts': uploadAttempts,
        'lastError': lastError,
      };

  static Evidence? fromJson(Object? json) {
    if (json is! Map) return null;
    final Object? id = json['id'];
    final Object? originalPath = json['originalPath'];
    if (id is! String || originalPath is! String) return null;
    return Evidence(
      id: id,
      observationId: (json['observationId'] as String?) ?? '',
      type: EvidenceType.fromName(json['type']),
      role: EvidenceRole.fromName(json['role']),
      originalPath: originalPath,
      uploadPath: json['uploadPath'] as String?,
      aiPath: json['aiPath'] as String?,
      thumbnailPath: json['thumbnailPath'] as String?,
      mimeType: (json['mimeType'] as String?) ?? 'application/octet-stream',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      durationMs: (json['durationMs'] as num?)?.toInt(),
      sha256: (json['sha256'] as String?) ?? '',
      perceptualHash: json['perceptualHash'] as String?,
      capturedAt: DateTime.tryParse('${json['capturedAt']}') ?? DateTime.now(),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      locationAccuracyMeters:
          (json['locationAccuracyMeters'] as num?)?.toDouble(),
      uploadState: SyncState.fromName(json['uploadState']),
      serverId: json['serverId'] as String?,
      captureSource: (json['captureSource'] as String?) ?? 'device-camera',
      uploadAttempts: (json['uploadAttempts'] as num?)?.toInt() ?? 0,
      lastError: json['lastError'] as String?,
    );
  }
}
