import 'dart:async';

import '../engines/notification_engine.dart';
import '../models/complaint.dart';
import 'complaint_event_service.dart';
import 'notification_service.dart';

/// Bridges domain events to the notification store AND lets the repository
/// react to a real-time "push" from the authority side (inspector / crew /
/// supervisor). It also simulates a live WebSocket feed advancing workflow
/// stages while the app is open.
class RealTimeComplaintService {
  RealTimeComplaintService();

  final NotificationService _notificationService = NotificationService();

  /// Incoming external status updates (as if pushed from a backend).
  final StreamController<ComplaintStatus> _external = StreamController.broadcast();
  Stream<ComplaintStatus> get externalUpdates => _external.stream;

  NotificationService get notifications => _notificationService;

  StreamSubscription<ComplaintDomainEvent>? _sub;

  void start() {
    _sub ??= ComplaintEventService.instance.events.listen((event) {
      _handle(event);
    });
  }

  void _handle(ComplaintDomainEvent event) {
    switch (event.type) {
      case ComplaintEventType.statusChanged:
        _notificationService.add(NotificationEngine.instance
            .forStatusChange(event.complaint, event.complaint.status));
        break;
      case ComplaintEventType.delayDetected:
        _notificationService.add(NotificationEngine.instance
            .forDelay(event.complaint, event.complaint.delayReason ?? 'Supervisor'));
        break;
      case ComplaintEventType.escalated:
        _notificationService.add(NotificationEngine.instance
            .forEscalation(event.complaint, event.meta ?? 'Authority'));
        break;
      default:
        break;
    }
  }

  void emitExternal(ComplaintStatus status) {
    _external.add(status);
  }

  void dispose() {
    _sub?.cancel();
    _notificationService.dispose();
  }
}
