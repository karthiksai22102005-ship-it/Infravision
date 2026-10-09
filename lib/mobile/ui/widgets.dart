import 'dart:io';

import 'package:flutter/material.dart';

import '../models/analysis.dart';
import '../models/observation.dart';

/// Byte size formatter that never prints "undefined" or fake precision.
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const List<String> units = <String>['B', 'KB', 'MB', 'GB'];
  double value = bytes.toDouble();
  int unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 100 || unit == 0 ? 0 : 1)} '
      '${units[unit]}';
}

/// Relative time label built from real timestamps only.
String timeAgo(DateTime when) {
  final Duration diff = DateTime.now().difference(when);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inDays < 7) return '${diff.inDays} d ago';
  return '${when.day}/${when.month}/${when.year}';
}

Color severityColor(SeverityLevel level) => switch (level) {
      SeverityLevel.critical => const Color(0xFFE5484D),
      SeverityLevel.high => const Color(0xFFF76B15),
      SeverityLevel.moderate => const Color(0xFFF5D90A),
      SeverityLevel.low => const Color(0xFF46A758),
    };

Color priorityColor(PriorityLevel level) => switch (level) {
      PriorityLevel.p0 => const Color(0xFFE5484D),
      PriorityLevel.p1 => const Color(0xFFF76B15),
      PriorityLevel.p2 => const Color(0xFF3B9EFF),
      PriorityLevel.p3 => const Color(0xFF8A8F98),
    };

Color syncColor(SyncState state) => switch (state) {
      SyncState.synced || SyncState.serverAccepted || SyncState.uploaded =>
        const Color(0xFF46A758),
      SyncState.failed => const Color(0xFFE5484D),
      SyncState.uploading || SyncState.queued || SyncState.retrying =>
        const Color(0xFFF76B15),
      SyncState.local => const Color(0xFF8A8F98),
    };

/// Compact coloured label used across list tiles and detail headers (§52).
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.dense = false,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 7 : 10,
        vertical: dense ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: dense ? 11 : 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: dense ? 10 : 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class SeverityPill extends StatelessWidget {
  const SeverityPill({super.key, required this.level, this.dense = false});

  final SeverityLevel level;
  final bool dense;

  @override
  Widget build(BuildContext context) => Pill(
        label: level.label,
        color: severityColor(level),
        icon: Icons.warning_amber_rounded,
        dense: dense,
      );
}

class PriorityPill extends StatelessWidget {
  const PriorityPill({super.key, required this.level, this.dense = false});

  final PriorityLevel level;
  final bool dense;

  @override
  Widget build(BuildContext context) => Pill(
        label: level.name.toUpperCase(),
        color: priorityColor(level),
        icon: Icons.bolt_rounded,
        dense: dense,
      );
}

class SyncPill extends StatelessWidget {
  const SyncPill({super.key, required this.state, this.dense = false});

  final SyncState state;
  final bool dense;

  @override
  Widget build(BuildContext context) => Pill(
        label: state.label,
        color: syncColor(state),
        icon: Icons.cloud_upload_outlined,
        dense: dense,
      );
}

/// Titled surface used to group information without nesting cards (§52).
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.trailing,
    this.subtitle,
  });

  final String title;
  final Widget child;
  final IconData? icon;
  final Widget? trailing;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.hintColor),
                        ),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

/// Honest empty state: says why the list is empty and what to do next.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
    this.action,
  });

  final IconData icon;
  final String title;
  final String hint;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 44, color: theme.hintColor),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.hintColor),
            ),
            if (action != null) ...<Widget>[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Thumbnail rendered from a bounded derivative, never the full original
/// (§55). A missing file degrades to an icon instead of a red error box.
class EvidenceThumb extends StatelessWidget {
  const EvidenceThumb({
    super.key,
    required this.path,
    this.size = 64,
    this.radius = 10,
    this.isVideo = false,
  });

  final String path;
  final double size;
  final double radius;
  final bool isVideo;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Image.file(
              File(path),
              fit: BoxFit.cover,
              cacheWidth: size.toInt() * 2,
              errorBuilder:
                  (BuildContext c, Object error, StackTrace? stack) {
                return ColoredBox(
                  color: Colors.black26,
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white54,
                    size: size * 0.4,
                  ),
                );
              },
            ),
            if (isVideo)
              const Center(
                child: Icon(Icons.play_circle_fill, color: Colors.white70),
              ),
          ],
        ),
      ),
    );
  }
}

/// Quality-gate badge reporting exactly what the screen measured (§18).
class QualityPill extends StatelessWidget {
  const QualityPill({super.key, required this.grade, this.findings});

  final QualityGrade grade;
  final List<QualityFinding>? findings;

  @override
  Widget build(BuildContext context) {
    final (String label, Color color) = switch (grade) {
      QualityGrade.excellent => ('Sharp', const Color(0xFF46A758)),
      QualityGrade.acceptable => ('Usable', const Color(0xFF3B9EFF)),
      QualityGrade.poor => ('Retake advised', const Color(0xFFF76B15)),
      QualityGrade.unavailable => (
          'Quality not measured',
          const Color(0xFF8A8F98)
        ),
    };
    final String detail = findings == null || findings!.isEmpty
        ? label
        : findings!.map((QualityFinding f) => f.message).join(' · ');
    return Tooltip(
      message: detail,
      child: Pill(
        label: label,
        color: color,
        icon: Icons.photo_camera_outlined,
      ),
    );
  }
}
