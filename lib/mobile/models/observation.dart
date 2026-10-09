/// Pure-Dart domain models for the InfraVision Observation Portal (Android).
///
/// These types depend on nothing but `dart:core` so they can be unit-tested
/// and used inside background isolates without Flutter plugins.
library;

/// Local/remote lifecycle of an observation submission (§30, §90).
enum SyncState {
  local('Local only'),
  queued('Queued for sync'),
  uploading('Uploading'),
  uploaded('Uploaded'),
  serverAccepted('Server accepted'),
  synced('Synced'),
  retrying('Retrying'),
  failed('Failed');

  const SyncState(this.label);
  final String label;

  bool get isPending =>
      this == SyncState.local ||
      this == SyncState.queued ||
      this == SyncState.uploading ||
      this == SyncState.retrying;

  static SyncState fromName(Object? name) {
    for (final SyncState v in SyncState.values) {
      if (v.name == name) return v;
    }
    return SyncState.local;
  }
}

/// Human-visible report status. Only ever set from a confirmed source (§90).
enum ObservationStatus {
  draft('Draft'),
  savedLocally('Saved locally'),
  pendingSync('Pending sync'),
  uploading('Uploading'),
  serverAccepted('Server accepted'),
  underReview('Under review'),
  resolved('Resolved');

  const ObservationStatus(this.label);
  final String label;

  static ObservationStatus fromName(Object? name) {
    for (final ObservationStatus v in ObservationStatus.values) {
      if (v.name == name) return v;
    }
    return ObservationStatus.draft;
  }
}

/// Defect severity (§38) — kept independent from priority (§39).
enum SeverityLevel {
  low('Low', 0.25),
  moderate('Moderate', 0.5),
  high('High', 0.75),
  critical('Critical', 0.95);

  const SeverityLevel(this.label, this.weight);
  final String label;
  final double weight;

  static SeverityLevel fromScore(double score) {
    if (score >= 0.85) return SeverityLevel.critical;
    if (score >= 0.6) return SeverityLevel.high;
    if (score >= 0.35) return SeverityLevel.moderate;
    return SeverityLevel.low;
  }

  static SeverityLevel fromName(Object? name) {
    for (final SeverityLevel v in SeverityLevel.values) {
      if (v.name == name || v.label == name) return v;
    }
    return SeverityLevel.moderate;
  }
}

/// Operational priority (§39) — how soon the defect must be handled.
enum PriorityLevel {
  p0('P0 — Immediate', 0),
  p1('P1 — Urgent', 1),
  p2('P2 — Scheduled', 2),
  p3('P3 — Routine', 3);

  const PriorityLevel(this.label, this.rank);
  final String label;
  final int rank;

  static PriorityLevel fromScore(double score) {
    if (score >= 80) return PriorityLevel.p0;
    if (score >= 60) return PriorityLevel.p1;
    if (score >= 35) return PriorityLevel.p2;
    return PriorityLevel.p3;
  }

  static PriorityLevel fromName(Object? name) {
    for (final PriorityLevel v in PriorityLevel.values) {
      if (v.name == name || v.label == name) return v;
    }
    return PriorityLevel.p2;
  }
}
/// A single GNSS/fused-location reading attached to an observation (§21/24).
class LocationFix {
  const LocationFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.timestamp,
    this.altitudeMeters,
    this.headingDegrees,
    this.speedMetersPerSecond,
    this.isMocked = false,
    this.isApproximatePermission = false,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime timestamp;
  final double? altitudeMeters;
  final double? headingDegrees;
  final double? speedMetersPerSecond;

  /// True when the platform reports a mock location provider.
  final bool isMocked;

  /// True when the user granted only approximate location (Android 12+).
  final bool isApproximatePermission;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'latitude': latitude,
        'longitude': longitude,
        'accuracyMeters': accuracyMeters,
        'timestamp': timestamp.toIso8601String(),
        'altitudeMeters': altitudeMeters,
        'headingDegrees': headingDegrees,
        'speedMetersPerSecond': speedMetersPerSecond,
        'isMocked': isMocked,
        'isApproximatePermission': isApproximatePermission,
      };

  static LocationFix? fromJson(Object? json) {
    if (json is! Map) return null;
    final Object? lat = json['latitude'];
    final Object? lon = json['longitude'];
    if (lat is! num || lon is! num) return null;
    return LocationFix(
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
      accuracyMeters: (json['accuracyMeters'] as num?)?.toDouble() ?? -1,
      timestamp: DateTime.tryParse('${json['timestamp']}') ?? DateTime.now(),
      altitudeMeters: (json['altitudeMeters'] as num?)?.toDouble(),
      headingDegrees: (json['headingDegrees'] as num?)?.toDouble(),
      speedMetersPerSecond: (json['speedMetersPerSecond'] as num?)?.toDouble(),
      isMocked: json['isMocked'] == true,
      isApproximatePermission: json['isApproximatePermission'] == true,
    );
  }
}
/// One field observation / infrastructure defect report (§42).
///
/// `toApiJson()` matches the documented backend contract so the mobile client
/// stays API-ready even while it is running fully offline.
class Observation {
  const Observation({
    required this.id,
    required this.clientId,
    required this.createdAt,
    required this.updatedAt,
    required this.observerId,
    required this.category,
    required this.description,
    required this.severity,
    required this.severityScore,
    required this.priority,
    required this.priorityScore,
    required this.location,
    this.subcategory,
    this.addressHint,
    this.aiConfidence,
    this.aiModelVersion,
    this.aiSuggestedCategory,
    this.categoryCorrectedByUser = false,
    this.status = ObservationStatus.draft,
    this.syncState = SyncState.local,
    this.evidenceIds = const <String>[],
    this.caseId,
    this.serverId,
    this.duplicateOfId,
    this.attempts = 0,
    this.nextAttemptAt,
    this.lastError,
    this.submittedAt,
    this.schemaVersion = currentSchemaVersion,
  });

  static const int currentSchemaVersion = 2;

  /// Local primary key (equals the client-generated id).
  final String id;

  /// Client-generated identifier used for duplicate protection (§33).
  final String clientId;

  final DateTime createdAt;
  final DateTime updatedAt;
  final String observerId;

  final String category;
  final String? subcategory;
  final String description;

  final SeverityLevel severity;
  final double severityScore;
  final PriorityLevel priority;
  final double priorityScore;

  final LocationFix location;
  final String? addressHint;

  final double? aiConfidence;
  final String? aiModelVersion;

  /// What the on-device model suggested (kept even when the user overrides).
  final String? aiSuggestedCategory;

  /// True when a human corrected the AI category (§41).
  final bool categoryCorrectedByUser;

  final ObservationStatus status;
  final SyncState syncState;
  final List<String> evidenceIds;

  /// Backend identifiers — only ever set after a confirmed server response.
  final String? caseId;
  final String? serverId;

  final String? duplicateOfId;

  final int attempts;
  final DateTime? nextAttemptAt;
  final String? lastError;
  final DateTime? submittedAt;

  final int schemaVersion;

  /// Submitted observations are immutable: evidence may not be edited (§15).
  bool get isLocked =>
      status != ObservationStatus.draft &&
      status != ObservationStatus.savedLocally;

  bool get hasConfirmedServerRecord =>
      caseId != null || serverId != null || syncState == SyncState.synced;

  Observation copyWith({
    DateTime? updatedAt,
    String? category,
    String? subcategory,
    String? description,
    SeverityLevel? severity,
    double? severityScore,
    PriorityLevel? priority,
    double? priorityScore,
    LocationFix? location,
    String? addressHint,
    double? aiConfidence,
    String? aiModelVersion,
    String? aiSuggestedCategory,
    bool? categoryCorrectedByUser,
    ObservationStatus? status,
    SyncState? syncState,
    List<String>? evidenceIds,
    String? caseId,
    String? serverId,
    String? duplicateOfId,
    int? attempts,
    DateTime? nextAttemptAt,
    String? lastError,
    DateTime? submittedAt,
    bool clearLastError = false,
    bool clearNextAttempt = false,
  }) {
    return Observation(
      id: id,
      clientId: clientId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      observerId: observerId,
      category: category ?? this.category,
      subcategory: subcategory ?? this.subcategory,
      description: description ?? this.description,
      severity: severity ?? this.severity,
      severityScore: severityScore ?? this.severityScore,
      priority: priority ?? this.priority,
      priorityScore: priorityScore ?? this.priorityScore,
      location: location ?? this.location,
      addressHint: addressHint ?? this.addressHint,
      aiConfidence: aiConfidence ?? this.aiConfidence,
      aiModelVersion: aiModelVersion ?? this.aiModelVersion,
      aiSuggestedCategory: aiSuggestedCategory ?? this.aiSuggestedCategory,
      categoryCorrectedByUser:
          categoryCorrectedByUser ?? this.categoryCorrectedByUser,
      status: status ?? this.status,
      syncState: syncState ?? this.syncState,
      evidenceIds: evidenceIds ?? this.evidenceIds,
      caseId: caseId ?? this.caseId,
      serverId: serverId ?? this.serverId,
      duplicateOfId: duplicateOfId ?? this.duplicateOfId,
      attempts: attempts ?? this.attempts,
      nextAttemptAt:
          clearNextAttempt ? null : (nextAttemptAt ?? this.nextAttemptAt),
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      submittedAt: submittedAt ?? this.submittedAt,
      schemaVersion: schemaVersion,
    );
  }
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'clientId': clientId,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'observerId': observerId,
        'category': category,
        'subcategory': subcategory,
        'description': description,
        'severity': severity.name,
        'severityScore': severityScore,
        'priority': priority.name,
        'priorityScore': priorityScore,
        'latitude': location.latitude,
        'longitude': location.longitude,
        'locationAccuracy': location.accuracyMeters,
        'locationTimestamp': location.timestamp.toIso8601String(),
        'location': location.toJson(),
        'addressHint': addressHint,
        'aiConfidence': aiConfidence,
        'aiModelVersion': aiModelVersion,
        'aiSuggestedCategory': aiSuggestedCategory,
        'categoryCorrectedByUser': categoryCorrectedByUser,
        'status': status.name,
        'syncState': syncState.name,
        'evidenceIds': evidenceIds,
        'caseId': caseId,
        'serverId': serverId,
        'duplicateOfId': duplicateOfId,
        'attempts': attempts,
        'nextAttemptAt': nextAttemptAt?.toIso8601String(),
        'lastError': lastError,
        'submittedAt': submittedAt?.toIso8601String(),
        'schemaVersion': schemaVersion,
      };

  static Observation? fromJson(Object? json) {
    if (json is! Map) return null;
    final LocationFix? location = LocationFix.fromJson(json['location']);
    if (location == null) return null;
    final Object? id = json['id'];
    if (id is! String || id.isEmpty) return null;

    return Observation(
      id: id,
      clientId: (json['clientId'] as String?) ?? id,
      createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
      updatedAt: DateTime.tryParse('${json['updatedAt']}') ?? DateTime.now(),
      observerId: (json['observerId'] as String?) ?? 'field-observer',
      category: (json['category'] as String?) ?? 'other',
      subcategory: json['subcategory'] as String?,
      description: (json['description'] as String?) ?? '',
      severity: SeverityLevel.fromName(json['severity']),
      severityScore: (json['severityScore'] as num?)?.toDouble() ?? 0.5,
      priority: PriorityLevel.fromName(json['priority']),
      priorityScore: (json['priorityScore'] as num?)?.toDouble() ?? 50,
      location: location,
      addressHint: json['addressHint'] as String?,
      aiConfidence: (json['aiConfidence'] as num?)?.toDouble(),
      aiModelVersion: json['aiModelVersion'] as String?,
      aiSuggestedCategory: json['aiSuggestedCategory'] as String?,
      categoryCorrectedByUser: json['categoryCorrectedByUser'] == true,
      status: ObservationStatus.fromName(json['status']),
      syncState: SyncState.fromName(json['syncState']),
      evidenceIds: <String>[
        if (json['evidenceIds'] is List)
          for (final Object? e in json['evidenceIds'] as List<Object?>)
            if (e is String) e,
      ],
      caseId: json['caseId'] as String?,
      serverId: json['serverId'] as String?,
      duplicateOfId: json['duplicateOfId'] as String?,
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      nextAttemptAt: DateTime.tryParse('${json['nextAttemptAt']}'),
      lastError: json['lastError'] as String?,
      submittedAt: DateTime.tryParse('${json['submittedAt']}'),
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ??
          Observation.currentSchemaVersion,
    );
  }

  /// Wire format for `POST /api/v1/observations` (§70).
  Map<String, dynamic> toApiJson() => <String, dynamic>{
        'clientId': clientId,
        'idempotencyKey': clientId,
        'observerId': observerId,
        'category': category,
        'subcategory': subcategory,
        'description': description,
        'severity': severity.name,
        'severityScore': severityScore,
        'priority': priority.name,
        'priorityScore': priorityScore,
        'ai': <String, dynamic>{
          'confidence': aiConfidence,
          'modelVersion': aiModelVersion,
          'suggestedCategory': aiSuggestedCategory,
          'correctedByUser': categoryCorrectedByUser,
        },
        'location': location.toJson(),
        'capturedAt': createdAt.toIso8601String(),
        'schemaVersion': schemaVersion,
      };
}
