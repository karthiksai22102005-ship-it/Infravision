import '../models/complaint.dart';

/// Generates the SLA deadline and human-friendly ETA for a complaint based on
/// its severity and priority. Also detects SLA breaches (delay detection).
class SLAEngine {
  SLAEngine._();

  static final SLAEngine instance = SLAEngine._();

  static const Duration criticalSla = Duration(hours: 24);
  static const Duration highSla = Duration(hours: 48);
  static const Duration moderateSla = Duration(days: 7);
  static const Duration lowSla = Duration(days: 14);

  String estimatedTimeFor(SeverityLevel severity) {
    switch (severity) {
      case SeverityLevel.critical:
        return '24 hours';
      case SeverityLevel.high:
        return '48 hours';
      case SeverityLevel.moderate:
        return '7 days';
      case SeverityLevel.low:
        return '14 days';
    }
  }

  Duration slaDurationFor(SeverityLevel severity) {
    switch (severity) {
      case SeverityLevel.critical:
        return criticalSla;
      case SeverityLevel.high:
        return highSla;
      case SeverityLevel.moderate:
        return moderateSla;
      case SeverityLevel.low:
        return lowSla;
    }
  }

  DateTime deadlineFor(SeverityLevel severity, {DateTime? from}) =>
      (from ?? DateTime.now()).add(slaDurationFor(severity));

  /// True when the complaint is still open and past its SLA deadline.
  bool isBreached(Complaint c) => c.isOverdue;

  /// How far past the deadline the complaint is (or zero).
  Duration breachDuration(Complaint c) {
    if (!isBreached(c)) return Duration.zero;
    return DateTime.now().difference(c.slaDeadline);
  }

  String remainingLabel(Complaint c) {
    if (c.isOverdue) {
      final d = breachDuration(c).inHours;
      return 'Delayed by ${d >= 24 ? '${(d / 24).floor()}d' : '${d}h'}';
    }
    final rem = c.remainingTime;
    if (rem.inHours >= 24) return 'ETA ${(rem.inHours / 24).floor()}d ${rem.inHours % 24}h';
    return 'ETA ${rem.inHours}h ${rem.inMinutes % 60}m';
  }
}
