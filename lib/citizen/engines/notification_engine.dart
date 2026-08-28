import 'dart:convert';

import '../models/complaint.dart';

/// A single in-app notification delivered to the citizen.
class NotificationItem {
  NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.timestamp,
    required this.caseId,
    required this.severity,
  });

  final String id;
  final String title;
  final String body;
  final DateTime timestamp;
  final String caseId;
  final int severity; // 0..2 for UI styling

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'timestamp': timestamp.toIso8601String(),
        'caseId': caseId,
        'severity': severity,
      };

  factory NotificationItem.fromJson(Map<String, dynamic> json) =>
      NotificationItem(
        id: json['id'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        caseId: json['caseId'] as String,
        severity: json['severity'] as int? ?? 0,
      );
}

/// Pure builder that converts lifecycle changes into human-readable
/// notifications (used by the repository + real-time service).
class NotificationEngine {
  NotificationEngine._();

  static final NotificationEngine instance = NotificationEngine._();

  NotificationItem forStatusChange(Complaint c, ComplaintStatus newStatus) {
    final sev = c.severity == SeverityLevel.critical
        ? 2
        : (c.severity == SeverityLevel.high ? 1 : 0);
    return NotificationItem(
      id: 'NTF-${DateTime.now().millisecondsSinceEpoch}',
      title: 'Case ${c.caseId} — ${newStatus.label}',
      body: '${c.category} ${_statusHelper(newStatus)}. '
          'Delivery status for ${c.assignedDepartment.isEmpty ? 'the responsible department' : c.assignedDepartment}.',
      timestamp: DateTime.now(),
      caseId: c.caseId,
      severity: sev,
    );
  }

  NotificationItem forDelay(Complaint c, String authority) {
    return NotificationItem(
      id: 'NTF-${DateTime.now().millisecondsSinceEpoch}',
      title: '⚠️ DELAY on ${c.caseId}',
      body: 'Expected resolution time has passed. Escalated to $authority. '
          'You do not need to keep checking — you will be notified on each change.',
      timestamp: DateTime.now(),
      caseId: c.caseId,
      severity: 2,
    );
  }

  NotificationItem forEscalation(Complaint c, String authority) {
    return NotificationItem(
      id: 'NTF-${DateTime.now().millisecondsSinceEpoch}',
      title: 'Case ${c.caseId} escalated',
      body: 'Advanced to $authority following escalation rules.',
      timestamp: DateTime.now(),
      caseId: c.caseId,
      severity: 1,
    );
  }

  String _statusHelper(ComplaintStatus s) {
    switch (s) {
      case ComplaintStatus.submitted:
        return 'report filed and queued for AI analysis.';
      case ComplaintStatus.aiAnalysisCompleted:
        return 'AI analysis completed and severity assessed.';
      case ComplaintStatus.duplicateCheckCompleted:
        return 'duplicate check completed.';
      case ComplaintStatus.departmentAssigned:
        return 'automatically routed to the correct department.';
      case ComplaintStatus.inspectorVerification:
        return 'scheduled for inspector verification.';
      case ComplaintStatus.repairTeamAssigned:
        return 'a repair team has been assigned.';
      case ComplaintStatus.workStarted:
        return 'repair work has started on site.';
      case ComplaintStatus.repairCompleted:
        return 'repair has been reported as completed.';
      case ComplaintStatus.qualityVerification:
        return 'is undergoing quality verification.';
      case ComplaintStatus.citizenConfirmation:
        return 'awaiting your confirmation.';
      case ComplaintStatus.closed:
        return 'case is now closed.';
    }
  }
}

/// Debug helper to serialize a batch of notifications (used in tests).
String encodeNotifications(List<NotificationItem> items) =>
    jsonEncode(items.map((e) => e.toJson()).toList());
