import 'dart:convert';
import 'dart:math' as math;

import 'timeline_event.dart';
import 'complaint_evidence.dart';

/// Severity of the physical defect (computed by the on-device AI + human).
enum SeverityLevel {
  low('Low', 0.25),
  moderate('Moderate', 0.5),
  high('High', 0.75),
  critical('Critical', 0.95);

  const SeverityLevel(this.label, this.weight);
  final String label;
  final double weight;

  static SeverityLevel fromName(Object? name) {
    if (name == null) return SeverityLevel.moderate;
    for (final v in SeverityLevel.values) {
      if (v.name == name || v.label == name) return v;
    }
    return SeverityLevel.moderate;
  }
}

/// Priority assigned by the [PriorityEngine] (0-100 score + label).
enum ComplaintPriorityLevel {
  low('Low', 25),
  medium('Medium', 50),
  high('High', 75),
  critical('Critical', 95);

  const ComplaintPriorityLevel(this.label, this.defaultScore);
  final String label;
  final int defaultScore;

  static ComplaintPriorityLevel fromScore(double score) {
    if (score >= 80) return ComplaintPriorityLevel.critical;
    if (score >= 60) return ComplaintPriorityLevel.high;
    if (score >= 40) return ComplaintPriorityLevel.medium;
    return ComplaintPriorityLevel.low;
  }
}

/// Full 11-stage event-based lifecycle shared across every section.
enum ComplaintStatus {
  submitted('Report Submitted'),
  aiAnalysisCompleted('AI Analysis Completed'),
  duplicateCheckCompleted('Duplicate Check Completed'),
  departmentAssigned('Department Assigned'),
  inspectorVerification('Inspector Verification'),
  repairTeamAssigned('Repair Team Assigned'),
  workStarted('Work Started'),
  repairCompleted('Repair Completed'),
  qualityVerification('Quality Verification'),
  citizenConfirmation('Citizen Confirmation'),
  closed('Closed');

  const ComplaintStatus(this.label);
  final String label;

  int get order => index;
  bool get isOpen => this != ComplaintStatus.closed;

  static ComplaintStatus fromName(Object? name) {
    if (name == null) return ComplaintStatus.submitted;
    for (final v in ComplaintStatus.values) {
      if (v.name == name || v.label == name) return v;
    }
    return ComplaintStatus.submitted;
  }
}

/// Extra metadata describing a citizen action on a shared issue.
enum CitizenAction {
  confirm('Confirm Same Issue'),
  follow('Follow Updates'),
  addEvidence('Add Evidence'),
  reopen('Reopen'),
  poorQuality('Report Poor Quality'),
  rate('Rate Service');

  const CitizenAction(this.label);
  final String label;
}

/// The shared complaint data model.
///
/// One instance flows through Quick Report -> My Reports -> Nearby Issues ->
/// Community Hub. All mutations go through [ComplaintRepository].
class Complaint {
  Complaint({
    required this.id,
    required this.caseId,
    required this.citizenId,
    required this.category,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.severity,
    required this.priorityScore,
    required this.createdAt,
    required this.estimatedResolutionTime,
    required this.slaDeadline,
    this.images = const [],
    this.videos = const [],
    this.priority = ComplaintPriorityLevel.medium,
    this.status = ComplaintStatus.submitted,
    this.assignedDepartment = '',
    this.assignedOfficerId,
    this.assignedCrewId,
    this.updatedAt,
    this.assignedAt,
    this.workStartedAt,
    this.resolvedAt,
    this.verifiedAt,
    this.escalationLevel = 0,
    this.duplicateDetected = false,
    this.parentComplaintId,
    this.confirmationCount = 1,
    this.followerCount = 0,
    this.citizenConfirmed = true,
    this.citizenRating,
    this.timeline = const [],
    this.evidence = const [],
    this.delayReason,
    this.resolutionEvidence = const [],
    this.aiConfidence,
    this.aiDiagnosis,
    this.sourceRef,
  });

  factory Complaint.fromJson(Map<String, dynamic> json) {
    return Complaint(
      id: json['id'] as String,
      caseId: json['caseId'] as String,
      citizenId: json['citizenId'] as String,
      category: json['category'] as String,
      description: json['description'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      address: json['address'] as String? ?? '',
      severity: SeverityLevel.fromName(json['severity']),
      priorityScore: (json['priorityScore'] as num?)?.toDouble() ?? 50,
      createdAt: DateTime.parse(json['createdAt'] as String),
      estimatedResolutionTime:
          json['estimatedResolutionTime'] as String? ?? '7 days',
      slaDeadline: DateTime.parse(json['slaDeadline'] as String),
      images: (json['images'] as List<dynamic>?)?.cast<String>() ?? const [],
      videos: (json['videos'] as List<dynamic>?)?.cast<String>() ?? const [],
      status: ComplaintStatus.fromName(json['status']),
      assignedDepartment: json['assignedDepartment'] as String? ?? '',
      assignedOfficerId: json['assignedOfficerId'] as String?,
      assignedCrewId: json['assignedCrewId'] as String?,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
      assignedAt: json['assignedAt'] != null
          ? DateTime.parse(json['assignedAt'] as String)
          : null,
      workStartedAt: json['workStartedAt'] != null
          ? DateTime.parse(json['workStartedAt'] as String)
          : null,
      resolvedAt: json['resolvedAt'] != null
          ? DateTime.parse(json['resolvedAt'] as String)
          : null,
      verifiedAt: json['verifiedAt'] != null
          ? DateTime.parse(json['verifiedAt'] as String)
          : null,
      escalationLevel: json['escalationLevel'] as int? ?? 0,
      duplicateDetected: json['duplicateDetected'] as bool? ?? false,
      parentComplaintId: json['parentComplaintId'] as String?,
      confirmationCount: json['confirmationCount'] as int? ?? 1,
      followerCount: json['followerCount'] as int? ?? 0,
      citizenConfirmed: json['citizenConfirmed'] as bool? ?? true,
      citizenRating: (json['citizenRating'] as num?)?.toInt(),
      timeline: (json['timeline'] as List<dynamic>? ?? const [])
          .map((e) => TimelineEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
      evidence: ((json['evidence'] as List<dynamic>?) ?? const [])
          .map((e) => ComplaintEvidence.fromJson(e as Map<String, dynamic>))
          .toList(),
      delayReason: json['delayReason'] as String?,
      resolutionEvidence:
          ((json['resolutionEvidence'] as List<dynamic>?) ?? const [])
              .map((e) =>
                  ComplaintEvidence.fromJson(e as Map<String, dynamic>))
              .toList(),
      aiConfidence: (json['aiConfidence'] as num?)?.toDouble(),
      aiDiagnosis: json['aiDiagnosis'] as String?,
      sourceRef: json['sourceRef'] as String?,
    );
  }

  final String id;
  String caseId;
  final String citizenId;
  String category;
  String description;
  double latitude;
  double longitude;
  String address;
  SeverityLevel severity;
  ComplaintPriorityLevel priority;
  double priorityScore;
  ComplaintStatus status;
  String assignedDepartment;
  String? assignedOfficerId;
  String? assignedCrewId;
  final DateTime createdAt;
  final String estimatedResolutionTime;
  DateTime slaDeadline;
  DateTime? updatedAt;
  DateTime? assignedAt;
  DateTime? workStartedAt;
  DateTime? resolvedAt;
  DateTime? verifiedAt;
  int escalationLevel;
  bool duplicateDetected;
  String? parentComplaintId;
  int confirmationCount;
  int followerCount;
  bool citizenConfirmed;
  int? citizenRating;
  List<String> images;
  List<String> videos;
  List<TimelineEvent> timeline;
  List<ComplaintEvidence> evidence;
  String? delayReason;
  List<ComplaintEvidence> resolutionEvidence;
  double? aiConfidence;
  String? aiDiagnosis;

  /// Legacy/authority cross-reference (e.g. the supervisor workspace's
  /// CMP-/CASE- identifiers) linking this shared complaint back to the
  /// portal-side record so lifecycle actions mirror in both directions.
  String? sourceRef;

  bool get isOpen => status.isOpen;
  bool get isOverdue => isOpen && DateTime.now().isAfter(slaDeadline);
  Duration get remainingTime => slaDeadline.difference(DateTime.now());
  int get affectedCitizenCount => confirmationCount;

  /// Haversine distance in meters from this complaint to a coordinate.
  double distanceTo(double lat, double lon) {
    const r = 6371000.0; // earth radius in meters
    final dLat = _rad(lat - latitude);
    final dLon = _rad(lon - longitude);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(latitude)) *
            math.cos(_rad(lat)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double deg) => deg * math.pi / 180.0;

  /// Most recent timeline event (used as the "Latest update" chip).
  TimelineEvent? get latestEvent => timeline.isEmpty
      ? null
      : timeline.reduce((a, b) => a.timestamp.isAfter(b.timestamp) ? a : b);

  List<ComplaintEvidence> get allEvidence => [...evidence, ...resolutionEvidence];

  Map<String, dynamic> toJson() => {
        'id': id,
        'caseId': caseId,
        'citizenId': citizenId,
        'category': category,
        'description': description,
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
        'severity': severity.name,
        'priority': priority.name,
        'priorityScore': priorityScore,
        'status': status.name,
        'assignedDepartment': assignedDepartment,
        'assignedOfficerId': assignedOfficerId,
        'assignedCrewId': assignedCrewId,
        'createdAt': createdAt.toIso8601String(),
        'estimatedResolutionTime': estimatedResolutionTime,
        'slaDeadline': slaDeadline.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'assignedAt': assignedAt?.toIso8601String(),
        'workStartedAt': workStartedAt?.toIso8601String(),
        'resolvedAt': resolvedAt?.toIso8601String(),
        'verifiedAt': verifiedAt?.toIso8601String(),
        'escalationLevel': escalationLevel,
        'duplicateDetected': duplicateDetected,
        'parentComplaintId': parentComplaintId,
        'confirmationCount': confirmationCount,
        'followerCount': followerCount,
        'citizenConfirmed': citizenConfirmed,
        'citizenRating': citizenRating,
        'timeline': timeline.map((e) => e.toJson()).toList(),
        'evidence': evidence.map((e) => e.toJson()).toList(),
        'delayReason': delayReason,
        'resolutionEvidence': resolutionEvidence.map((e) => e.toJson()).toList(),
        'aiConfidence': aiConfidence,
        'aiDiagnosis': aiDiagnosis,
        'sourceRef': sourceRef,
      };

  @override
  String toString() => jsonEncode(toJson());
}


