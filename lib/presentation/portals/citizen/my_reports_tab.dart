import 'dart:io';

import 'package:flutter/material.dart';

import '../../../config/app_theme.dart';
import '../../../citizen/models/complaint.dart';
import '../../../citizen/repository/complaint_repository.dart';
import 'complaint_detail_view.dart';

/// TAB 2 — My Reports: full real-time complaint management & tracking.
class MyReportsTab extends StatefulWidget {
  const MyReportsTab({super.key});

  @override
  State<MyReportsTab> createState() => _MyReportsTabState();
}

class _MyReportsTabState extends State<MyReportsTab> {
  void _openDetail(Complaint c) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ComplaintDetailView(complaint: c),
    ));
  }

  void _showNotifications(ComplaintRepository repo) {
    repo.notifications.markAllSeen();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgSurface,
        title: const Text('Notifications', style: TextStyle(color: AppTheme.textPrimary)),
        content: SizedBox(
          width: 360,
          child: repo.notifications.items.isEmpty
              ? const Text('No updates yet.', style: TextStyle(color: AppTheme.textSecondary))
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final n in repo.notifications.items)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.campaign_rounded, color: AppTheme.cyan),
                        title: Text(n.title, style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
                        subtitle: Text('${n.body}\n${_fmt(n.timestamp)}', style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
                      ),
                  ],
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close', style: TextStyle(color: AppTheme.textSecondary)))],
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    final repo = ComplaintRepository.instance;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final mine = repo.myReports;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(children: [
                const Expanded(
                  child: Text('My Reports & Real-Time Tracking',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
                ),
                ListenableBuilder(
                  listenable: repo.notifications,
                  builder: (context, _) => IconButton(
                    onPressed: () => _showNotifications(repo),
                    icon: Badge(
                      isLabelVisible: repo.notifications.unseen > 0,
                      label: Text('${repo.notifications.unseen}'),
                      child: const Icon(Icons.notifications_rounded, color: AppTheme.textPrimary),
                    ),
                    tooltip: 'Notifications',
                  ),
                ),
              ]),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Every status change from inspectors, crews and supervisors appears here '
                'and as a notification — no need to keep checking the app.',
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: mine.isEmpty
                  ? const Center(child: Text('No reports yet. Use Quick Report to file one.', style: TextStyle(color: AppTheme.textMuted)))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: mine.length,
                      itemBuilder: (context, i) => _card(mine[i]),
                    ),
            ),
          ],
        );
      },
    );
  }
  Widget _card(Complaint c) {
    final overdue = c.isOverdue;
    return Card(
      color: AppTheme.bgSurface,
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openDetail(c),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                if (c.images.isNotEmpty && File(c.images.first).existsSync())
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(File(c.images.first), width: 46, height: 46, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                  )
                else
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(color: AppTheme.bgSurfaceSubtle, borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.image_not_supported_rounded, color: AppTheme.textMuted, size: 20),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Case ${c.caseId}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.cyan, fontFamily: 'monospace')),
                    Text(c.category,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                    Text('${_fmt(c.createdAt)}  •  ${c.assignedDepartment.isEmpty ? 'Routing…' : c.assignedDepartment}',
                        style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
                  ]),
                ),
                Icon(overdue ? Icons.warning_amber_rounded : Icons.chevron_right_rounded,
                    color: overdue ? AppTheme.error : AppTheme.textMuted, size: 20),
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                _chip(c.status.label, AppTheme.cyan),
                _chip(c.priority.label, _priorityColor(c)),
                _chip(overdue ? '⚠ ${SLAEngineLabel.eta(c)}' : SLAEngineLabel.eta(c), overdue ? AppTheme.error : AppTheme.success),
              ]),
              if (c.latestEvent != null) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: AppTheme.bgSurfaceSubtle, borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    'Last update: ${c.latestEvent!.title} — ${c.latestEvent!.description}',
                    style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withValues(alpha: 0.4))),
        child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
      );

  Color _priorityColor(Complaint c) => switch (c.priority) {
        ComplaintPriorityLevel.critical => AppTheme.error,
        ComplaintPriorityLevel.high => AppTheme.warning,
        ComplaintPriorityLevel.medium => AppTheme.cyan,
        ComplaintPriorityLevel.low => AppTheme.success,
      };

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
