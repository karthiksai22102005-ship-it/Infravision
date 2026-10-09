/// DOMAIN-INDEPENDENT PHYSICAL ISSUE — the persistent identity of one
/// real-world problem. Many heterogeneous [Observation]s correlate into one
/// PhysicalIssue; one PhysicalIssue drives one-or-more existing cases,
/// tasks and work orders through its lifecycle.
library;

enum IssueLifecycleState {
  candidate('Candidate'),
  identified('Identified'),
  verificationRequired('Verification Required'),
  verified('Verified'),
  assigned('Assigned'),
  inProgress('In Progress'),
  resolutionSubmitted('Resolution Submitted'),
  reverificationRequired('Reverification Required'),
  resolved('Resolved'),
  persistent('Persistent'),
  escalated('Escalated'),
  closed('Closed');

  const IssueLifecycleState(this.label);
  final String label;

  static IssueLifecycleState fromName(Object? name) =>
      values.firstWhere((v) => v.name == name,
          orElse: () => IssueLifecycleState.candidate);

  bool get isOpen =>
      this != IssueLifecycleState.resolved &&
      this != IssueLifecycleState.closed;
}

/// One field/manager verification pass over a PhysicalIssue.
class VerificationRecord {
  VerificationRecord({
    required this.verificationId,
    required this.physicalIssueId,
    required this.verdict,
    required this.verifiedByActorType,
    required this.verifiedByActorId,
    required this.timestamp,
    this.notes = '',
    this.evidencePaths = const [],
  });

  /// 'passed' | 'failed' | 'pending'
  final String verdict;
  final String verificationId;
  final String physicalIssueId;
  final String verifiedByActorType;
  final String verifiedByActorId;
  final DateTime timestamp;
  final String notes;
  final List<String> evidencePaths;

  Map<String, dynamic> toJson() => {
        'verificationId': verificationId,
        'physicalIssueId': physicalIssueId,
        'verdict': verdict,
        'verifiedByActorType': verifiedByActorType,
        'verifiedByActorId': verifiedByActorId,
        'timestamp': timestamp.toIso8601String(),
        'notes': notes,
        'evidencePaths': evidencePaths,
      };

  factory VerificationRecord.fromJson(Map<String, dynamic> json) =>
      VerificationRecord(
        verificationId: json['verificationId'] as String,
        physicalIssueId: json['physicalIssueId'] as String,
        verdict: json['verdict'] as String,
        verifiedByActorType: json['verifiedByActorType'] as String,
        verifiedByActorId: json['verifiedByActorId'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        notes: json['notes'] as String? ?? '',
        evidencePaths:
            (json['evidencePaths'] as List<dynamic>?)?.cast<String>() ??
                const [],
      );
}

/// One attempt by a resolution team to fix the issue.
class ResolutionAttempt {
  ResolutionAttempt({
    required this.attemptId,
    required this.taskRef,
    required this.teamRef,
    required this.startedAt,
    this.submittedAt,
    this.evidencePaths = const [],
    this.outcome = 'pending',
  });

  final String attemptId;

  /// Cross-reference into the existing Task/WorkOrder/Case model.
  final String taskRef;
  final String teamRef;
  final DateTime startedAt;
  DateTime? submittedAt;
  List<String> evidencePaths;

  /// 'pending' | 'resolved' | 'persistent'
  String outcome;

  Map<String, dynamic> toJson() => {
        'attemptId': attemptId,
        'taskRef': taskRef,
        'teamRef': teamRef,
        'startedAt': startedAt.toIso8601String(),
        'submittedAt': submittedAt?.toIso8601String(),
        'evidencePaths': evidencePaths,
        'outcome': outcome,
      };

  factory ResolutionAttempt.fromJson(Map<String, dynamic> json) =>
      ResolutionAttempt(
        attemptId: json['attemptId'] as String,
        taskRef: json['taskRef'] as String,
        teamRef: json['teamRef'] as String,
        startedAt: DateTime.parse(json['startedAt'] as String),
        submittedAt: json['submittedAt'] != null
            ? DateTime.parse(json['submittedAt'] as String)
            : null,
        evidencePaths:
            (json['evidencePaths'] as List<dynamic>?)?.cast<String>() ??
                const [],
        outcome: json['outcome'] as String? ?? 'pending',
      );
}

class PhysicalIssue {
  PhysicalIssue({
    required this.physicalIssueId,
    required this.domain,
    required this.issueType,
    required this.primaryLat,
    required this.primaryLng,
    this.locationBoundary,
    this.status = IssueLifecycleState.candidate,
    this.identityConfidence = 0.5,
    required this.createdAt,
    DateTime? updatedAt,
    List<String> observationIds = const [],
    List<VerificationRecord> verificationHistory = const [],
    List<String> taskRefs = const [],
    List<ResolutionAttempt> resolutionAttempts = const [],
    this.title = '',
    this.address = '',
  })  : updatedAt = updatedAt ?? createdAt,
        observationIds = List.of(observationIds),
        verificationHistory = List.of(verificationHistory),
        taskRefs = List.of(taskRefs),
        resolutionAttempts = List.of(resolutionAttempts);

  factory PhysicalIssue.fromJson(Map<String, dynamic> json) => PhysicalIssue(
        physicalIssueId: json['physicalIssueId'] as String,
        domain: json['domain'] as String,
        issueType: json['issueType'] as String,
        primaryLat: (json['primaryLat'] as num).toDouble(),
        primaryLng: (json['primaryLng'] as num).toDouble(),
        locationBoundary: json['locationBoundary'] as String?,
        status: IssueLifecycleState.fromName(json['status']),
        identityConfidence:
            (json['identityConfidence'] as num?)?.toDouble() ?? 0.5,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: json['updatedAt'] != null
            ? DateTime.parse(json['updatedAt'] as String)
            : null,
        observationIds:
            (json['observationIds'] as List<dynamic>?)?.cast<String>() ??
                const [],
        verificationHistory: ((json['verificationHistory'] as List<dynamic>?) ??
                const [])
            .map((e) => VerificationRecord.fromJson(e as Map<String, dynamic>))
            .toList(),
        taskRefs:
            (json['taskRefs'] as List<dynamic>?)?.cast<String>() ?? const [],
        resolutionAttempts: ((json['resolutionAttempts'] as List<dynamic>?) ??
                const [])
            .map((e) => ResolutionAttempt.fromJson(e as Map<String, dynamic>))
            .toList(),
        title: json['title'] as String? ?? '',
        address: json['address'] as String? ?? '',
      );

  /// Persistent identity: the same real-world problem keeps this ID forever,
  /// regardless of who observed it, on what device, through which portal.
  final String physicalIssueId;
  final String domain;
  String issueType;
  double primaryLat;
  double primaryLng;
  String? locationBoundary;
  IssueLifecycleState status;
  double identityConfidence;
  final DateTime createdAt;
  DateTime updatedAt;

  final List<String> observationIds;
  final List<VerificationRecord> verificationHistory;
  final List<String> taskRefs;
  final List<ResolutionAttempt> resolutionAttempts;
  String title;
  String address;

  Map<String, dynamic> toJson() => {
        'physicalIssueId': physicalIssueId,
        'domain': domain,
        'issueType': issueType,
        'primaryLat': primaryLat,
        'primaryLng': primaryLng,
        'locationBoundary': locationBoundary,
        'status': status.name,
        'identityConfidence': identityConfidence,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'observationIds': observationIds,
        'verificationHistory':
            verificationHistory.map((v) => v.toJson()).toList(),
        'taskRefs': taskRefs,
        'resolutionAttempts':
            resolutionAttempts.map((r) => r.toJson()).toList(),
        'title': title,
        'address': address,
      };
}

