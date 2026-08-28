import 'dart:async';

import '../models/complaint.dart';

/// A domain event broadcast through the shared lifecycle whenever a complaint
/// changes. Both the real-time service and notification service subscribe to
/// this stream so every section (My Reports / Nearby / Community Hub / in-app
/// notifications) updates automatically from one event source.
enum ComplaintEventType {
  created,
  statusChanged,
  confirmed,
  followed,
  evidenceAdded,
  escalated,
  delayDetected,
  resolved,
  citizenResponded,
  synced,

  /// Fired once [ComplaintRepository] finished loading/creating data so any
  /// queued authority-side mirrors (inspector logs, work orders, closures)
  /// recorded while the citizen stack was asleep can be replayed safely.
  repositoryReady,
}

class ComplaintDomainEvent {
  const ComplaintDomainEvent({
    required this.type,
    required this.complaint,
    this.meta,
  });

  final ComplaintEventType type;
  final Complaint complaint;
  final String? meta;
}

class ComplaintEventService {
  ComplaintEventService._();

  static final ComplaintEventService instance = ComplaintEventService._();

  final StreamController<ComplaintDomainEvent> _controller =
      StreamController.broadcast();

  Stream<ComplaintDomainEvent> get events => _controller.stream;

  void publish(ComplaintDomainEvent event) {
    if (!_controller.isClosed) _controller.add(event);
  }

  void dispose() => _controller.close();
}
