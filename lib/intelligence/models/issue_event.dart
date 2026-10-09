/// IMMUTABLE ISSUE EVENT — one entry in a PhysicalIssue's timeline.
/// Every correlation, lifecycle transition, assignment, resolution and
/// verification automatically appends an IssueEvent.
library;

enum IssueEventType {
  observationAdded('Observation Added'),
  matchedExisting('Matched Existing Issue'),
  matchUncertain('Uncertain Match — Review Required'),
  newIssueCreated('New Physical Issue Created'),
  lifecycleChanged('Lifecycle Updated'),
  fieldVerified('Field Verified'),
  taskAssigned('Task Assigned'),
  workStarted('Work Started'),
  resolutionSubmitted('Resolution Evidence Submitted'),
  verificationPassed('Verification Passed'),
  verificationFailed('Verification Failed'),
  escalated('Escalated'),
  reopened('Reopened'),
  closed('Closed'),
  noteAdded('Note Added');

  const IssueEventType(this.label);
  final String label;

  static IssueEventType fromName(Object? name) =>
      values.firstWhere((v) => v.name == name,
          orElse: () => IssueEventType.noteAdded);
}

class IssueEvent {
  IssueEvent({
    required this.eventId,
    required this.physicalIssueId,
    required this.eventType,
    required this.actorType,
    required this.actorId,
    this.sourceReference,
    required this.timestamp,
    this.description = '',
    this.metadata = const {},
  });

  factory IssueEvent.fromJson(Map<String, dynamic> json) => IssueEvent(
        eventId: json['eventId'] as String,
        physicalIssueId: json['physicalIssueId'] as String,
        eventType: IssueEventType.fromName(json['eventType']),
        actorType: json['actorType'] as String,
        actorId: json['actorId'] as String,
        sourceReference: json['sourceReference'] as String?,
        timestamp: DateTime.parse(json['timestamp'] as String),
        description: json['description'] as String? ?? '',
        metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
      );

  final String eventId;
  final String physicalIssueId;
  final IssueEventType eventType;

  /// Generic actors: 'reporter' | 'fieldAgent' | 'resolutionTeam' |
  /// 'operationsManager' | 'ai' | 'system'.
  final String actorType;
  final String actorId;

  /// Cross-reference to the producing record (observation id, case id…).
  final String? sourceReference;
  final DateTime timestamp;
  final String description;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'physicalIssueId': physicalIssueId,
        'eventType': eventType.name,
        'actorType': actorType,
        'actorId': actorId,
        'sourceReference': sourceReference,
        'timestamp': timestamp.toIso8601String(),
        'description': description,
        'metadata': metadata,
      };
}
