import 'dart:io';

import 'package:flutter/material.dart';

import '../../../config/app_theme.dart';
import '../../../citizen/models/complaint.dart';
import '../../../citizen/repository/complaint_repository.dart';
import 'complaint_detail_view.dart';

/// TAB 4 — Community Hub: community infrastructure issue & resolution hub
/// (NOT a social platform). Shows trending/most-confirmed/high-impact issues,
/// before & after repair evidence, community confirmations, progress and
/// resolution ratings, plus reopen / poor-quality escalation for resolved work.
class CommunityHubTab extends StatefulWidget {
  const CommunityHubTab({super.key});

  @override
  State<CommunityHubTab> createState() => _CommunityHubTabState();
}

class _CommunityHubTabState extends State<CommunityHubTab> {
  void _openDetail(Complaint c) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ComplaintDetailView(complaint: c)));
  }

  @override
  Widget build(BuildContext context) {
    final repo = ComplaintRepository.instance;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final public = repo.publicIssues;
        final resolved = repo.resolvedIssues;
        final trending = List.of(repo.communityTrending).take(4).toList();
        final mostConfirmed = List.of(public)
          ..sort((a, b) => b.confirmationCount.compareTo(a.confirmationCount));
        final highImpact = public.where((c) => c.isOpen).toList()
          ..sort((a, b) => b.priorityScore.compareTo(a.priorityScore));

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Community Infrastructure Hub',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
            const SizedBox(height: 4),
            const Text(
                'Community verification, impact tracking, evidence, progress and resolution monitoring — '
                'not a social feed.',
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _stat('Issues Fixed', '${resolved.length}', AppTheme.success)),
              const SizedBox(width: 10),
              Expanded(child: _stat('Active Issues', '${public.where((c) => c.isOpen).length}', AppTheme.warning)),
            ]),
            const SizedBox(height: 16),
            _section('Trending Public Issues', trending, repo),
            _section('Most Confirmed Issues', mostConfirmed.take(3).toList(), repo),
            _section('High-Impact Unresolved', highImpact.take(3).toList(), repo),
            _sectionResolved('Recently Resolved — Before & After', resolved.take(3).toList(), repo),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
  Widget _section(String title, List<Complaint> items, ComplaintRepository repo) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
          const SizedBox(height: 6),
          if (items.isEmpty)
            const Text('No issues yet.', style: TextStyle(fontSize: 11, color: AppTheme.textMuted))
          else
            for (final c in items) _issueCard(c, repo),
        ],
      ),
    );
  }

  Widget _sectionResolved(String title, List<Complaint> items, ComplaintRepository repo) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
          const SizedBox(height: 6),
          if (items.isEmpty)
            const Text('No resolved issues yet.', style: TextStyle(fontSize: 11, color: AppTheme.textMuted))
          else
            for (final c in items) _resolvedCard(c),
        ],
      ),
    );
  }
  Widget _issueCard(Complaint c, ComplaintRepository repo) {
    final isFollowed = repo.followedIds.contains(c.id);
    return Card(
      color: AppTheme.bgSurface,
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _openDetail(c),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(c.category,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                ),
                _chip(c.priority.label, _priorityColor(c)),
              ]),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                _chip(c.status.label, AppTheme.cyan),
                _chip('${c.confirmationCount} confirmations', AppTheme.warning),
                _chip('${c.followerCount} followers', AppTheme.purple),
                _chip('Impact ${c.priorityScore.round()}/100', _priorityColor(c)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: AppTheme.success, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                  onPressed: () => repo.confirmIssue(c.id),
                  icon: const Icon(Icons.verified_rounded, size: 14),
                  label: const Text('Confirm', style: TextStyle(fontSize: 10)),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: AppTheme.purple, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                  onPressed: () => repo.followIssue(c.id, follow: !isFollowed),
                  icon: Icon(isFollowed ? Icons.notifications_off_rounded : Icons.notifications_rounded, size: 14),
                  label: Text(isFollowed ? 'Following' : 'Follow', style: const TextStyle(fontSize: 10)),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
  Widget _resolvedCard(Complaint c) {
    return Card(
      color: AppTheme.success.withValues(alpha: 0.06),
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _openDetail(c),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${c.category} — RESOLVED', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.success)),
              const SizedBox(height: 4),
              Text(
                  'Completed ${c.resolvedAt != null ? _fmt(c.resolvedAt!) : 'n/a'}  •  Verified: ${c.verifiedAt != null ? 'Yes' : 'No'}  •  '
                  'Satisfaction: ${c.citizenRating != null ? '${'★' * c.citizenRating!}/5' : 'pending'}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
              if (c.resolutionEvidence.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 64,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    for (final e in c.resolutionEvidence)
                      if (File(e.path).existsSync())
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(File(e.path), width: 64, height: 64, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const SizedBox.shrink())),
                        ),
                  ]),
                ),
              ],
              const SizedBox(height: 8),
              const Text('Tap to view progress, resolution proof, or rate / reopen.',
                  style: TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
  Widget _stat(String label, String value, Color color) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppTheme.bgSurface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
          Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
        ]),
      );

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
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
