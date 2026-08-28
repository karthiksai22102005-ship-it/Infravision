import 'dart:convert';

import 'complaint.dart';

/// A single event in the shared complaint lifecycle timeline.
///
/// Replaces the old static status-only flow with a full event-based log.
/// Every status transition, confirmation, evidence upload, dispatch, and
/// escalation produces a `TimelineEvent` that all four Citizen sections,
/// the repository, and the engine layer subscribe to.
class TimelineEvent {
  TimelineEvent({
    required this.id,
    required this.complaintId,
    required this.title,
    required this.description,
    required this.status,
    required this.timestamp,
    required this.actor,
    required this.actorType,
    this.metadata = const {},
  });

  factory TimelineEvent.fromJson(Map<String, dynamic> json) {
    return TimelineEvent(
      id: json['id'] as String,
      complaintId: json['complaintId'] as String,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      status: ComplaintStatus.fromName(json['status'] as String?),
      timestamp: DateTime.parse(json['timestamp'] as String),
      actor: json['actor'] as String? ?? 'Citizen',
      actorType: json['actorType'] as String? ?? 'citizen',
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
    );
  }

  final String id;
  final String complaintId;
  final String title;
  final String description;
  final ComplaintStatus status;
  final DateTime timestamp;
  final String actor; // e.g. "Citizen", "Inspector R. Mehta", "Crew 04", "PWD"
  final String actorType; // citizen | inspector | crew | supervisor | system
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => {
        'id': id,
        'complaintId': complaintId,
        'title': title,
        'description': description,
        'status': status.name,
        'timestamp': timestamp.toIso8601String(),
        'actor': actor,
        'actorType': actorType,
        'metadata': metadata,
      };

  @override
  String toString() => jsonEncode(toJson());
}
