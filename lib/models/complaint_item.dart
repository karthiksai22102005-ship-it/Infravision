import 'dart:convert';

enum ComplaintStatus {
  submitted('Submitted', 'Waiting for triage review'),
  triaged('Triaged', 'Verified by inspector'),
  dispatched('Dispatched', 'Assigned to repair division'),
  resolved('Resolved', 'Repair completed & verified');

  const ComplaintStatus(this.displayName, this.description);
  final String displayName;
  final String description;
}

enum ComplaintSeverity {
  critical('Critical', 'Immediate public safety risk (24h SLA)'),
  high('High', 'Severe structural/road degradation (48h SLA)'),
  moderate('Moderate', 'Standard maintenance issue (7-day SLA)'),
  low('Low', 'Minor cosmetic / low risk (14-day SLA)');

  const ComplaintSeverity(this.displayName, this.description);
  final String displayName;
  final String description;
}

class ComplaintItem {
  ComplaintItem({
    required this.id,
    required this.title,
    required this.category,
    required this.zone,
    required this.severity,
    required this.severityScore,
    required this.status,
    required this.createdAt,
    required this.slaDeadline,
    this.evidencePaths = const [],
    this.inspectorNotes = '',
    this.linkedCaseId,
    this.gpsCoordinates,
    this.department = 'Public Works Department (PWD)',
  });

  factory ComplaintItem.fromJson(Map<String, dynamic> json) {
    return ComplaintItem(
      id: json['id'] as String,
      title: json['title'] as String,
      category: json['category'] as String,
      zone: json['zone'] as String,
      severity: ComplaintSeverity.values.firstWhere(
        (e) => e.name == json['severity'],
        orElse: () => ComplaintSeverity.moderate,
      ),
      severityScore: (json['severityScore'] as num?)?.toDouble() ?? 0.5,
      status: ComplaintStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => ComplaintStatus.submitted,
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      slaDeadline: DateTime.parse(json['slaDeadline'] as String),
      evidencePaths: (json['evidencePaths'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      inspectorNotes: json['inspectorNotes'] as String? ?? '',
      linkedCaseId: json['linkedCaseId'] as String?,
      gpsCoordinates: json['gpsCoordinates'] as String?,
      department: json['department'] as String? ?? 'Public Works Department (PWD)',
    );
  }

  final String id;
  final String title;
  final String category;
  final String zone;
  final ComplaintSeverity severity;
  final double severityScore;
  ComplaintStatus status;
  final DateTime createdAt;
  final DateTime slaDeadline;
  final List<String> evidencePaths;
  String inspectorNotes;
  String? linkedCaseId;
  final String? gpsCoordinates;
  final String department;

  bool get isOverdue => DateTime.now().isAfter(slaDeadline) && status != ComplaintStatus.resolved;

  Duration get remainingTime => slaDeadline.difference(DateTime.now());

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'category': category,
        'zone': zone,
        'severity': severity.name,
        'severityScore': severityScore,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'slaDeadline': slaDeadline.toIso8601String(),
        'evidencePaths': evidencePaths,
        'inspectorNotes': inspectorNotes,
        'linkedCaseId': linkedCaseId,
        'gpsCoordinates': gpsCoordinates,
        'department': department,
      };

  @override
  String toString() => jsonEncode(toJson());
}
