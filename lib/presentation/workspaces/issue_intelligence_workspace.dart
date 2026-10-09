import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../intelligence/issue_intelligence_engine.dart';
import '../../intelligence/models/issue_event.dart';
import '../../intelligence/models/observation.dart';
import '../../intelligence/models/physical_issue.dart';

/// SUPERVISOR WORKSPACE — the single connected view over the intelligence
/// layer: uncertain match queue, verification queue, persistent issues and
/// the full PhysicalIssue timeline with observation history.
class IssueIntelligenceWorkspace extends StatelessWidget {
  const IssueIntelligenceWorkspace({super.key});

  @override
  Widget build(BuildContext context) {
    final engine = IssueIntelligenceEngine.instance;
    return ListenableBuilder(
      listenable: engine,
      builder: (context, _) => DefaultTabController(
        length: 4,
        child: Column(
          children: [
            _summaryStrip(engine),
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: AppTheme.cyan,
              unselectedLabelColor: AppTheme.textMuted,
              indicatorColor: AppTheme.cyan,
              tabs: [
                Tab(text: 'Uncertain (${engine.uncertainMatchQueue.length})'),
                Tab(text: 'Verification (${engine.verificationQueue.length})'),
                Tab(text: 'Persistent (${engine.persistentIssues.length})'),
                Tab(text: 'All Issues (${engine.issues.length})'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _UncertainQueue(engine: engine),
                  _VerificationQueue(engine: engine),
                  _IssueList(engine: engine, issues: engine.persistentIssues),
                  _IssueList(engine: engine, issues: engine.issues),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryStrip(IssueIntelligenceEngine engine) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.hub_rounded, color: AppTheme.cyan, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${engine.domain.displayName} · '
              '${engine.issues.length} physical issues · '
              '${engine.observations.length} observations · '
              '${engine.openIssues.length} open',
              style:
                  const TextStyle(fontSize: 11, color: AppTheme.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _UncertainQueue extends StatelessWidget {
  const _UncertainQueue({required this.engine});
  final IssueIntelligenceEngine engine;

  @override
  Widget build(BuildContext context) {
    final queue = engine.uncertainMatchQueue;
    if (queue.isEmpty) return _empty('No uncertain matches awaiting review.');
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: queue.length,
      itemBuilder: (context, i) {
        final obs = queue[i];
        final issue = obs.relatedPhysicalIssueId != null
            ? engine.issueById(obs.relatedPhysicalIssueId!)
            : null;
        return Card(
          color: AppTheme.bgSurface,
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${obs.detectedIssueType ?? obs.classification ?? 'Unclassified'}'
                  '  ·  ${obs.sourceType.label}',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  'Candidate: ${issue?.physicalIssueId ?? '?'} · '
                  '${obs.timestamp.month}/${obs.timestamp.day} '
                  '${obs.timestamp.hour}:${obs.timestamp.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.warning),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.success,
                          padding:
                              const EdgeInsets.symmetric(vertical: 8)),
                      onPressed: () => engine.resolveUncertainMatch(
                          observationId: obs.observationId, accept: true),
                      icon: const Icon(Icons.link_rounded, size: 16),
                      label: const Text('Same issue — link',
                          style: TextStyle(fontSize: 11)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.error,
                          padding:
                              const EdgeInsets.symmetric(vertical: 8)),
                      onPressed: () => engine.resolveUncertainMatch(
                          observationId: obs.observationId, accept: false),
                      icon: const Icon(Icons.link_off_rounded, size: 16),
                      label: const Text('Different issue',
                          style: TextStyle(fontSize: 11)),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _VerificationQueue extends StatelessWidget {
  const _VerificationQueue({required this.engine});
  final IssueIntelligenceEngine engine;

  @override
  Widget build(BuildContext context) {
    final queue = engine.verificationQueue;
    if (queue.isEmpty) {
      return _empty('No issues awaiting result verification.');
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: queue.length,
      itemBuilder: (context, i) => _issueCard(context, engine, queue[i],
          actions: (issue) => [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.success,
                        padding:
                            const EdgeInsets.symmetric(vertical: 8)),
                    onPressed: () => engine.verifyResolution(
                        issue.physicalIssueId,
                        passed: true),
                    icon: const Icon(Icons.task_alt_rounded, size: 16),
                    label: const Text('No longer exists — resolve',
                        style: TextStyle(fontSize: 11)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.error,
                        padding:
                            const EdgeInsets.symmetric(vertical: 8)),
                    onPressed: () => engine.verifyResolution(
                        issue.physicalIssueId,
                        passed: false),
                    icon: const Icon(Icons.report_rounded, size: 16),
                    label: const Text('Still active — persistent',
                        style: TextStyle(fontSize: 11)),
                  ),
                ),
              ]),
    );
  }
}

class _IssueList extends StatelessWidget {
  const _IssueList({required this.engine, required this.issues});
  final IssueIntelligenceEngine engine;
  final List<PhysicalIssue> issues;

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) return _empty('No physical issues recorded yet.');
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: issues.length,
      itemBuilder: (context, i) =>
          _issueCard(context, engine, issues[i], actions: null),
    );
  }
}

Widget _empty(String text) => Center(
      child: Text(text, style: const TextStyle(color: AppTheme.textMuted)),
    );

Widget _issueCard(
  BuildContext context,
  IssueIntelligenceEngine engine,
  PhysicalIssue issue, {
  List<Widget> Function(PhysicalIssue issue)? actions,
}) {
  final lifecycleColor = switch (issue.status) {
    IssueLifecycleState.persistent => AppTheme.error,
    IssueLifecycleState.resolved || IssueLifecycleState.closed => AppTheme.success,
    IssueLifecycleState.verificationRequired ||
    IssueLifecycleState.reverificationRequired =>
      AppTheme.warning,
    _ => AppTheme.cyan,
  };
  return Card(
    color: AppTheme.bgSurface,
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                '${issue.physicalIssueId} · ${issue.issueType}',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary),
              ),
            ),
            _chip(issue.status.label, lifecycleColor),
          ]),
          const SizedBox(height: 2),
          Text(
            '${issue.observationIds.length} observations · '
            'identity ${(issue.identityConfidence * 100).round()}% · '
            '${issue.verificationHistory.length} verifications'
            '${issue.address.isEmpty ? '' : ' · ${issue.address}'}',
            style: const TextStyle(fontSize: 11, color: AppTheme.cyan),
          ),
          const SizedBox(height: 8),
          if (actions != null) ...[
            Row(children: actions(issue)),
            const SizedBox(height: 8),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _openTimeline(context, engine, issue),
              icon: const Icon(Icons.timeline_rounded, size: 14),
              label: const Text('View full timeline & observations',
                  style: TextStyle(fontSize: 11)),
            ),
          ),
        ],
      ),
    ),
  );
}

void _openTimeline(BuildContext context, IssueIntelligenceEngine engine,
    PhysicalIssue issue) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.bgCanvas,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.all(16),
        children: [
          Text('PI TIMELINE — ${issue.physicalIssueId}',
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.cyan)),
          const SizedBox(height: 4),
          Text(
            '${issue.issueType} · ${issue.status.label} · '
            'identity ${(issue.identityConfidence * 100).round()}%',
            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 12),
          for (final e in engine.timelineOf(issue.physicalIssueId)) _eventTile(e),
          const SizedBox(height: 16),
          const Text('OBSERVATION HISTORY',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.cyan)),
          const SizedBox(height: 6),
          for (final id in issue.observationIds)
            _observationTile(engine.observationById(id)),
        ],
      ),
    ),
  );
}

Widget _eventTile(IssueEvent e) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 86,
            child: Text(
              '${e.timestamp.month}/${e.timestamp.day} '
              '${e.timestamp.hour.toString().padLeft(2, '0')}:'
              '${e.timestamp.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
            ),
          ),
          const Icon(Icons.circle, size: 6, color: AppTheme.cyan),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.eventType.label,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary)),
                if (e.description.isNotEmpty)
                  Text(e.description,
                      style: const TextStyle(
                          fontSize: 10, color: AppTheme.textMuted)),
                Text('by ${e.actorType}/${e.actorId}',
                    style: const TextStyle(fontSize: 9, color: AppTheme.purple)),
              ],
            ),
          ),
        ],
      ),
    );

Widget _observationTile(Observation? obs) {
  if (obs == null) return const SizedBox.shrink();
  return Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: AppTheme.bgSurface,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppTheme.border),
    ),
    child: Text(
      '${obs.observationId} · ${obs.sourceType.label} · ${obs.status.label}'
      '${obs.media.isNotEmpty ? ' · ${obs.media.length} media' : ''}',
      style: const TextStyle(fontSize: 10, color: AppTheme.textPrimary),
    ),
  );
}

Widget _chip(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );



