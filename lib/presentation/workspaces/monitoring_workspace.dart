import 'dart:async';
import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/monitoring_event.dart';
import '../../repositories/app_storage.dart';

enum _EventCategory { all, camera, complaint, caseEvent, system }

/// Enhanced Live Activity Telemetry & Event Bus Stream.
class MonitoringWorkspace extends StatefulWidget {
  const MonitoringWorkspace({super.key});

  @override
  State<MonitoringWorkspace> createState() => _MonitoringWorkspaceState();
}

class _MonitoringWorkspaceState extends State<MonitoringWorkspace>
    with TickerProviderStateMixin {
  _EventCategory _category = _EventCategory.all;
  late AnimationController _liveCtrl;
  late Animation<double> _liveAnim;
  Timer? _ticker;
  int _tickCount = 0;

  @override
  void initState() {
    super.initState();
    _liveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _liveAnim = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _liveCtrl, curve: Curves.easeInOut),
    );
    // Simulate live event ticker every 8 seconds
    _ticker = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted) setState(() => _tickCount++);
    });
  }

  @override
  void dispose() {
    _liveCtrl.dispose();
    _ticker?.cancel();
    super.dispose();
  }

  List<MonitoringEvent> _filtered(List<MonitoringEvent> all) {
    switch (_category) {
      case _EventCategory.all:
        return all;
      case _EventCategory.camera:
        return all.where((e) => e.category == 'camera').toList();
      case _EventCategory.complaint:
        return all.where((e) => e.category == 'complaint').toList();
      case _EventCategory.caseEvent:
        return all.where((e) => e.category == 'case').toList();
      case _EventCategory.system:
        return all.where((e) => e.category == 'system').toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AppTheme.isMobile(context);

    return ListenableBuilder(
      listenable: AppStorage.instance,
      builder: (context, _) {
        final all = AppStorage.instance.eventsList;
        final events = _filtered(all);

        return Column(
          children: [
            // Header with live pulse
            _buildHeader(context, all.length),
            // Category filter bar
            _buildCategoryBar(context),
            // Stats strip
            _buildStatsStrip(context, all),
            // Event timeline
            Expanded(
              child: events.isEmpty
                  ? _buildEmptyState(context)
                  : ListView.builder(
                      padding: EdgeInsets.all(isMobile ? 14 : 20),
                      reverse: true,
                      itemCount: events.length,
                      itemBuilder: (context, idx) {
                        final event = events[events.length - 1 - idx];
                        return _EventCard(
                          event: event,
                          isLatest: idx == 0,
                          liveAnim: _liveAnim,
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, int totalEvents) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      decoration: const BoxDecoration(
        color: AppTheme.bgSurface,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _liveAnim,
            builder: (context, _) => Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: AppTheme.success
                    .withValues(alpha: _liveAnim.value),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.success
                        .withValues(alpha: _liveAnim.value * 0.6),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'LIVE',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppTheme.success,
                letterSpacing: 1.5),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Activity Telemetry & Event Bus Stream',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary),
                ),
                SizedBox(height: 1),
                Text(
                  'Chronological sensor inputs, triage events, and repair verification logs.',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.primaryLight,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: AppTheme.primary.withValues(alpha: 0.4)),
            ),
            child: Text(
              '$totalEvents Events',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBar(BuildContext context) {
    final cats = [
      (_EventCategory.all, 'All', Icons.all_inclusive_rounded),
      (_EventCategory.camera, 'Camera', Icons.camera_alt_rounded),
      (_EventCategory.complaint, 'Complaints', Icons.report_rounded),
      (_EventCategory.caseEvent, 'Work Orders', Icons.build_circle_rounded),
      (_EventCategory.system, 'System', Icons.settings_rounded),
    ];

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppTheme.bgSurface,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          for (final cat in cats) ...[
            _CatPill(
              label: cat.$2,
              icon: cat.$3,
              isSelected: _category == cat.$1,
              onTap: () => setState(() => _category = cat.$1),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildStatsStrip(BuildContext context, List<MonitoringEvent> all) {
    final camCount =
        all.where((e) => e.category == 'camera').length;
    final complaintCount =
        all.where((e) => e.category == 'complaint').length;
    final caseCount =
        all.where((e) => e.category == 'case').length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: const BoxDecoration(
        color: AppTheme.bgSurfaceSubtle,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          _TinyMetric(
              label: 'Camera Events', value: '$camCount', color: AppTheme.cyan),
          const SizedBox(width: 20),
          _TinyMetric(
              label: 'Defect Reports',
              value: '$complaintCount',
              color: AppTheme.error),
          const SizedBox(width: 20),
          _TinyMetric(
              label: 'Work Orders',
              value: '$caseCount',
              color: AppTheme.primary),
          const Spacer(),
          Row(
            children: [
              AnimatedBuilder(
                animation: _liveAnim,
                builder: (context, _) => Icon(
                  Icons.circle,
                  size: 8,
                  color: AppTheme.success
                      .withValues(alpha: _liveAnim.value),
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'Real-time event stream active',
                style: TextStyle(
                    fontSize: 10,
                    color: AppTheme.textMuted,
                    fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: AppTheme.primaryLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.sensors_rounded,
                size: 40, color: AppTheme.primary),
          ),
          const SizedBox(height: 16),
          const Text('No Telemetry Events Yet',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary)),
          const SizedBox(height: 6),
          const Text(
            'Camera actions, complaint submissions, and\nrepair sign-offs stream here in real-time.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.isLatest,
    required this.liveAnim,
  });

  final MonitoringEvent event;
  final bool isLatest;
  final Animation<double> liveAnim;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final diff = now.difference(event.timestamp);
    final timeLabel = diff.inMinutes < 1
        ? 'Just now'
        : diff.inMinutes < 60
            ? '${diff.inMinutes}m ago'
            : diff.inHours < 24
                ? '${diff.inHours}h ago'
                : '${diff.inDays}d ago';

    final timeStr =
        '${event.timestamp.hour.toString().padLeft(2, '0')}:${event.timestamp.minute.toString().padLeft(2, '0')}:${event.timestamp.second.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline connector
          Column(
            children: [
              if (isLatest)
                AnimatedBuilder(
                  animation: liveAnim,
                  builder: (context, _) => Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: event.color,
                      boxShadow: [
                        BoxShadow(
                          color: event.color.withValues(alpha: liveAnim.value * 0.7),
                          blurRadius: 8,
                          spreadRadius: 3,
                        ),
                      ],
                    ),
                  ),
                )
              else
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: event.color.withValues(alpha: 0.5),
                    border: Border.all(color: event.color, width: 1.5),
                  ),
                ),
              Container(
                width: 2,
                height: 50,
                color: event.color.withValues(alpha: 0.15),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isLatest
                    ? event.color.withValues(alpha: 0.06)
                    : AppTheme.bgSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isLatest
                      ? event.color.withValues(alpha: 0.3)
                      : AppTheme.border,
                ),
                boxShadow: AppTheme.shadowSm,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: event.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(event.icon, color: event.color, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                event.title,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textPrimary),
                              ),
                            ),
                            if (isLatest)
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.success
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                      color: AppTheme.success
                                          .withValues(alpha: 0.4)),
                                ),
                                child: const Text(
                                  'NEW',
                                  style: TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.w900,
                                      color: AppTheme.success,
                                      letterSpacing: 1),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          event.subtitle,
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        timeStr,
                        style: const TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: AppTheme.textMuted),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        timeLabel,
                        style: TextStyle(
                            fontSize: 9,
                            color: isLatest
                                ? AppTheme.success
                                : AppTheme.textMuted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _CatPill extends StatelessWidget {
  const _CatPill({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? AppTheme.primaryLight : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: isSelected ? AppTheme.primary : AppTheme.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 13,
                  color: isSelected
                      ? AppTheme.primary
                      : AppTheme.textSecondary),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight:
                        isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected
                        ? AppTheme.primary
                        : AppTheme.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _TinyMetric extends StatelessWidget {
  const _TinyMetric(
      {required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          value,
          style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w800, color: color),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: AppTheme.textMuted),
        ),
      ],
    );
  }
}
