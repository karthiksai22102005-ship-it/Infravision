import 'dart:convert';

enum CaseStatus {
  assigned('Assigned', 'Work order issued to division'),
  inProgress('In Progress', 'Field repair team on-site'),
  repairCompleted('Repair Completed', 'Contractor reported work done'),
  awaitingVerification('Awaiting Verification', 'Pending post-repair photo inspection'),
  resolved('Resolved & Closed', 'Verified defect rectified');

  const CaseStatus(this.displayName, this.description);
  final String displayName;
  final String description;
}

class CaseItem {
  CaseItem({
    required this.id,
    required this.complaintId,
    required this.title,
    required this.department,
    required this.assignedTeam,
    required this.status,
    required this.priority,
    required this.beforeEvidencePath,
    required this.createdAt,
    required this.slaDeadline,
    this.afterEvidencePath,
    this.resolvedAt,
    this.verificationNotes = '',
    this.verificationPassed = false,
    this.assignedEngineer = 'Duty Engineer',
  });

  factory CaseItem.fromJson(Map<String, dynamic> json) {
    return CaseItem(
      id: json['id'] as String,
      complaintId: json['complaintId'] as String,
      title: json['title'] as String,
      department: json['department'] as String,
      assignedTeam: json['assignedTeam'] as String,
      status: CaseStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => CaseStatus.assigned,
      ),
      priority: json['priority'] as String? ?? 'High',
      beforeEvidencePath: json['beforeEvidencePath'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      slaDeadline: DateTime.parse(json['slaDeadline'] as String),
      afterEvidencePath: json['afterEvidencePath'] as String?,
      resolvedAt: json['resolvedAt'] != null ? DateTime.parse(json['resolvedAt'] as String) : null,
      verificationNotes: json['verificationNotes'] as String? ?? '',
      verificationPassed: json['verificationPassed'] as bool? ?? false,
      assignedEngineer: json['assignedEngineer'] as String? ?? 'Duty Engineer',
    );
  }

  final String id;
  final String complaintId;
  final String title;
  final String department;
  String assignedTeam;
  CaseStatus status;
  String priority;
  final String beforeEvidencePath;
  final DateTime createdAt;
  final DateTime slaDeadline;
  String? afterEvidencePath;
  DateTime? resolvedAt;
  String verificationNotes;
  bool verificationPassed;
  String assignedEngineer;

  bool get isOverdue => DateTime.now().isAfter(slaDeadline) && status != CaseStatus.resolved;
  Duration get remainingTime => slaDeadline.difference(DateTime.now());

  Map<String, dynamic> toJson() => {
        'id': id,
        'complaintId': complaintId,
        'title': title,
        'department': department,
        'assignedTeam': assignedTeam,
        'status': status.name,
        'priority': priority,
        'beforeEvidencePath': beforeEvidencePath,
        'createdAt': createdAt.toIso8601String(),
        'slaDeadline': slaDeadline.toIso8601String(),
        'afterEvidencePath': afterEvidencePath,
        'resolvedAt': resolvedAt?.toIso8601String(),
        'verificationNotes': verificationNotes,
        'verificationPassed': verificationPassed,
        'assignedEngineer': assignedEngineer,
      };

  @override
  String toString() => jsonEncode(toJson());
}
