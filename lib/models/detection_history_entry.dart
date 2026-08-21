/// In-memory record of a detected object event in the current session.
class DetectionHistoryEntry {
  DetectionHistoryEntry({
    required this.className,
    required this.confidence,
    required this.timestamp,
    this.count = 1,
  });

  final String className;
  final double confidence;
  final DateTime timestamp;
  int count;

  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
