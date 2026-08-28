import '../models/complaint.dart';
import 'sla_engine.dart';

/// Automatic escalation authority ladder for delayed / repeatedly-reported
/// complaints, following escalation rules when an SLA deadline is breached.
class EscalationEngine {
  EscalationEngine._();

  static final EscalationEngine instance = EscalationEngine._();

  /// Escalation ladder ordered by authority level (higher = more senior).
  static const List<String> _ladder = [
    'Frontline Work Crew',
    'Department Duty Engineer',
    'Zone Supervisor',
    'Municipal Commissioner Office',
  ];

  String authorityAtLevel(int level) {
    final idx = level.clamp(0, _ladder.length - 1);
    return _ladder[idx];
  }

  /// Should the complaint be escalated? True when its SLA is breached (or,
  /// for high-public-impact issues, when breach persists past a grace period).
  bool shouldEscalate(Complaint c) {
    if (!c.isOpen) return false;
    if (!SLAEngine.instance.isBreached(c)) return false;
    // Require a small grace period for relatively minor issues.
    if (c.severity == SeverityLevel.low) {
      return SLAEngine.instance.breachDuration(c).inHours >= 24;
    }
    return true;
  }

  /// Returns the next escalation level + responsible authority.
  (int, String) nextEscalation(Complaint c) {
    final next = c.escalationLevel + 1;
    final authority = authorityAtLevel(next);
    return (next, authority);
  }
}
