import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../config/app_theme.dart';
import '../../../citizen/models/complaint.dart';
import '../../../citizen/models/complaint_evidence.dart';
import '../../../citizen/repository/complaint_repository.dart';

/// Reusable full complaint detail + timeline + citizen actions view shared by
/// My Reports, Nearby Issues and Community Hub.
class ComplaintDetailView extends StatefulWidget {
  const ComplaintDetailView({super.key, required this.complaint});

  final Complaint complaint;

  @override
  State<ComplaintDetailView> createState() => _ComplaintDetailViewState();
}

class _ComplaintDetailViewState extends State<ComplaintDetailView> {
  final TextEditingController _comment = TextEditingController();
  bool _showCommentBox = false;

  Complaint get c => widget.complaint;

  Future<void> _pickEvidence({required bool resolution}) async {
    final picked = await FilePicker.pickFiles(
      type: FileType.media,
    );
    for (final f in picked) {
      if (f.path == null) continue;
      final ext = f.name.toLowerCase().split('.').last;
      final isVideo =
          const {'mp4', 'mov', 'avi', 'mkv', 'm4v', 'webm'}.contains(ext);
      ComplaintRepository.instance.addEvidence(
        c.id,
        path: f.path!,
        kind: isVideo ? EvidenceKind.video : EvidenceKind.image,
        caption: f.name,
        resolution: resolution,
      );
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Evidence attached to the case.'),
          behavior: SnackBarBehavior.floating));
    }
  }

  void _addComment() {
    if (_comment.text.trim().isEmpty) return;
    ComplaintRepository.instance.addComment(c.id, _comment.text);
    _comment.clear();
    FocusScope.of(context).unfocus();
  }

  void _showCommentField() => setState(() => _showCommentBox = true);

  void _confirmResolution(int rating) {
    ComplaintRepository.instance.resolveConfirm(c.id, satisfied: true, rating: rating);
    if (mounted) {
      Navigator.pop(context);
    }
  }
  void _showCommentDialog() {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgSurface,
        title: const Text('Confirm Resolution', style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text('Was the issue resolved to your satisfaction?',
            style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx, false);
            },
            child: const Text('Reject / Not resolved', style: TextStyle(color: AppTheme.error)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, resolved', style: TextStyle(color: AppTheme.success)),
          ),
        ],
      ),
    ).then((satisfied) {
      if (!mounted || satisfied == null) return;
      if (!satisfied) {
        ComplaintRepository.instance.resolveConfirm(c.id, satisfied: false);
        return;
      }
      _showRatingDialog();
    });
  }

  void _showRatingDialog() {
    showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgSurface,
        title: const Text('Rate this repair', style: TextStyle(color: AppTheme.textPrimary)),
        content: Wrap(spacing: 8, children: [for (var i = 1; i <= 5; i++) _ratingChip(ctx, i)]),
      ),
    ).then((rating) {
      if (rating != null) _confirmResolution(rating);
    });
  }

  Widget _ratingChip(BuildContext ctx, int rating) => ActionChip(
        label: Text('$rating★', style: const TextStyle(color: AppTheme.textPrimary)),
        backgroundColor: AppTheme.bgSurfaceSubtle,
        onPressed: () => Navigator.pop(ctx, rating),
      );

  void _showReopenDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          backgroundColor: AppTheme.bgSurface,
          title: const Text('Reopen Case / Report Poor Quality', style: TextStyle(color: AppTheme.textPrimary)),
          content: TextField(
            controller: controller,
            maxLines: 2,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(hintText: 'Reason (optional)'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
              onPressed: () {
                ComplaintRepository.instance.reportPoorQuality(c.id, controller.text);
                Navigator.pop(ctx);
              },
              child: const Text('Report & Reopen'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = ComplaintRepository.instance;
    return Scaffold(
      backgroundColor: AppTheme.bgCanvas,
      appBar: AppBar(
        backgroundColor: AppTheme.bgSurface,
        title: Text('Case ${c.caseId}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
      ),
      body: ListenableBuilder(
        listenable: repo,
        builder: (context, _) {
          final live = repo.byId(c.id) ?? c;
          final isFollowed = repo.followedIds.contains(c.id);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _header(live),
              const SizedBox(height: 14),
              _metaGrid(live),
              const SizedBox(height: 14),
              _resolutionPanel(live),
              const SizedBox(height: 14),
              _timeline(live),
              const SizedBox(height: 14),
              _actions(live, isFollowed),
            ],
          );
        },
      ),
    );
  }
  Widget _header(Complaint live) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (live.images.isNotEmpty && File(live.images.first).existsSync())
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(File(live.images.first), width: 64, height: 64, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          )
        else
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: AppTheme.bgSurfaceSubtle, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.image_not_supported_rounded, color: AppTheme.textMuted),
          ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(live.category,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, children: [
                _chip(live.status.label, AppTheme.cyan),
                _chip(live.priority.label, _priorityColor(live)),
                _chip(live.severity.label, _severityColor(live)),
              ]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _metaGrid(Complaint live) {
    final rows = <(String, String)>[
      ('Department', live.assignedDepartment.isEmpty ? 'Pending routing' : live.assignedDepartment),
      ('Inspector', live.assignedOfficerId ?? '—'),
      ('Crew', live.assignedCrewId ?? '—'),
      ('Reported', _fmt(live.createdAt)),
      ('SLA / ETA', SLAEngineLabel.eta(live)),
      ('Affected citizens', '${live.affectedCitizenCount}'),
      ('Followers', '${live.followerCount}'),
      ('Escalation', 'Level ${live.escalationLevel}'),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppTheme.bgSurface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.border)),
      child: Column(children: [
        for (final (k, v) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              SizedBox(width: 130, child: Text(k, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary))),
              Expanded(
                  child: Text(v,
                      style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary, fontWeight: FontWeight.w600))),
            ]),
          ),
      ]),
    );
  }

  Widget _resolutionPanel(Complaint live) {
    if (live.status != ComplaintStatus.closed) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppTheme.success.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.success.withValues(alpha: 0.3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Resolution status', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
          const SizedBox(height: 6),
          Text(
              'Completed: ${live.resolvedAt != null ? _fmt(live.resolvedAt!) : 'n/a'}  •  Verified: ${live.verifiedAt != null ? _fmt(live.verifiedAt!) : 'n/a'}',
              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
          if (live.citizenRating != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Citizen satisfaction: ${'★' * live.citizenRating!} /5',
                  style: const TextStyle(fontSize: 12, color: AppTheme.success, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }
  Widget _timeline(Complaint live) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppTheme.bgSurface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Lifecycle Timeline', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
          const SizedBox(height: 12),
          for (var i = 0; i < live.timeline.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(children: [
                  Icon(Icons.circle, size: 10, color: i == live.timeline.length - 1 ? AppTheme.cyan : AppTheme.textMuted),
                  if (i != live.timeline.length - 1) Container(width: 2, height: 28, color: AppTheme.border),
                ]),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(child: Text(live.timeline[i].title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textPrimary))),
                          Text(_fmt(live.timeline[i].timestamp), style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                        ]),
                        const SizedBox(height: 2),
                        Text(live.timeline[i].description, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                        const SizedBox(height: 2),
                        Text('by ${live.timeline[i].actor}', style: const TextStyle(fontSize: 10, color: AppTheme.cyan)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
  Widget _actions(Complaint live, bool isFollowed) {
    final canConfirm = live.status == ComplaintStatus.citizenConfirmation ||
        live.status == ComplaintStatus.closed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Citizen Actions', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppTheme.cyan),
            onPressed: () => _pickEvidence(resolution: false),
            icon: const Icon(Icons.add_photo_alternate_rounded, size: 16),
            label: const Text('Add Photo / Video'),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppTheme.purple),
            onPressed: _showCommentField,
            icon: const Icon(Icons.comment_rounded, size: 16),
            label: const Text('Comment'),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppTheme.textSecondary),
            onPressed: () => ComplaintRepository.instance.followIssue(live.id, follow: !isFollowed),
            icon: Icon(isFollowed ? Icons.notifications_off_rounded : Icons.notifications_rounded, size: 16),
            label: Text(isFollowed ? 'Unfollow' : 'Follow'),
          ),
          if (canConfirm)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.success),
              onPressed: _showCommentDialog,
              icon: const Icon(Icons.verified_rounded, size: 16),
              label: const Text('Confirm Resolution'),
            ),
          if (live.status == ComplaintStatus.closed)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: AppTheme.error, side: const BorderSide(color: AppTheme.error)),
              onPressed: _showReopenDialog,
              icon: const Icon(Icons.thumb_down_rounded, size: 16),
              label: const Text('Poor quality / Reopen'),
            ),
        ]),
        if (_showCommentBox)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _comment,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                  decoration: const InputDecoration(hintText: 'Add a comment to this case...'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(onPressed: _addComment, icon: const Icon(Icons.send_rounded, color: AppTheme.cyan)),
            ]),
          ),
      ],
    );
  }
  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.4))),
        child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
      );

  Color _priorityColor(Complaint c2) => switch (c2.priority) {
        ComplaintPriorityLevel.critical => AppTheme.error,
        ComplaintPriorityLevel.high => AppTheme.warning,
        ComplaintPriorityLevel.medium => AppTheme.cyan,
        ComplaintPriorityLevel.low => AppTheme.success,
      };

  Color _severityColor(Complaint c2) => switch (c2.severity) {
        SeverityLevel.critical || SeverityLevel.high => AppTheme.error,
        SeverityLevel.moderate => AppTheme.warning,
        SeverityLevel.low => AppTheme.success,
      };

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Shared textual SLA/ETA label helper used across citizen screens.
class SLAEngineLabel {
  SLAEngineLabel._();
  static String eta(Complaint c) {
    if (c.isOverdue) {
      final h = DateTime.now().difference(c.slaDeadline).inHours;
      return 'Delayed by ${h >= 24 ? '${(h / 24).floor()}d' : '${h}h'}';
    }
    final rem = c.remainingTime;
    if (rem.inHours >= 24) return 'ETA ${(rem.inHours / 24).floor()}d ${rem.inHours % 24}h';
    if (rem.inMinutes <= 0) return 'Due now';
    return 'ETA ${rem.inHours}h ${rem.inMinutes % 60}m';
  }
}
