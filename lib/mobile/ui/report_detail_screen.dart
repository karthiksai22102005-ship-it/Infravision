import 'package:flutter/material.dart';

import '../core/result.dart';
import '../models/evidence.dart';
import '../models/observation.dart';
import 'portal_services.dart';
import 'reports_screen.dart' show categoryLabel;
import 'widgets.dart';

/// Everything this device knows about one report: assessment, position,
/// evidence with per-item upload state, and the integrity check (§45/§73).
class ReportDetailScreen extends StatefulWidget {
  const ReportDetailScreen({super.key, required this.observationId});

  final String observationId;

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  bool _verifying = false;
  String? _message;

  Future<void> _syncNow() async {
    final PortalServices services = PortalScope.of(context);
    await services.repository.syncNow();
    if (!mounted) return;
    setState(() => _message = services.repository.lastSyncMessage);
  }

  Future<void> _verifyEvidence(Evidence evidence) async {
    final PortalServices services = PortalScope.of(context);
    setState(() => _verifying = true);
    final bool intact = await services.evidenceStore
        .verifyIntegrity(evidence.originalPath, evidence.sha256);
    if (!mounted) return;
    setState(() {
      _verifying = false;
      _message = intact
          ? 'SHA-256 matches the stored original — the evidence is intact.'
          : 'The original file does not match its recorded hash. Do not trust '
              'this capture; check the diagnostics log.';
    });
  }

  /// Only drafts may be deleted — submitted reports are never removed (§103).
  Future<void> _discardIfDraft(Observation observation) async {
    if (observation.status != ObservationStatus.draft) return;
    final PortalServices services = PortalScope.of(context);
    final Result<void> result =
        await services.repository.discardDraft(observation.id);
    if (!mounted) return;
    if (result is Err<void>) {
      setState(() => _message = result.failure.message);
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final PortalServices services = PortalScope.of(context);
    return ListenableBuilder(
      listenable: services.repository,
      builder: (BuildContext context, Widget? child) {
        final Observation? observation =
            services.database.observationById(widget.observationId);
        if (observation == null) {
          return const Scaffold(
            body: EmptyState(
              icon: Icons.delete_outline,
              title: 'Report no longer on this device',
              hint: 'It may have been removed from the storage folder.',
            ),
          );
        }
        final List<Evidence> evidence =
            services.database.evidenceForObservation(observation.id);
        return Scaffold(
          appBar: AppBar(title: Text(categoryLabel(observation.category))),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 28),
            children: <Widget>[
              _HeaderCard(observation: observation),
              SectionCard(
                title: 'Position',
                icon: Icons.gps_fixed,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${observation.location.latitude.toStringAsFixed(6)}, '
                      '${observation.location.longitude.toStringAsFixed(6)}',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    Text(
                      '±${observation.location.accuracyMeters.toStringAsFixed(1)} m'
                      ' · recorded ${timeAgo(observation.location.timestamp)}'
                      '${observation.location.isMocked ? ' · MOCKED location' : ''}'
                      '${observation.location.isApproximatePermission ? ' · approximate permission' : ''}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (observation.description.isNotEmpty)
                SectionCard(
                  title: 'Description',
                  icon: Icons.notes_outlined,
                  child: Text(observation.description),
                ),
              SectionCard(
                title: 'Evidence (${evidence.length})',
                icon: Icons.photo_library_outlined,
                subtitle: 'Thumbnails stay bounded — originals are untouched',
                child: evidence.isEmpty
                    ? const Text('No evidence is stored for this report.')
                    : GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 120,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 0.78,
                        ),
                        itemCount: evidence.length,
                        itemBuilder: (BuildContext context, int index) =>
                            _EvidenceTile(
                          evidence: evidence[index],
                          onTap: () => _showEvidence(evidence[index]),
                        ),
                      ),
              ),
              _SyncCard(observation: observation, onSync: _syncNow),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: Text(
                    _message!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (observation.status == ObservationStatus.draft)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
                  child: OutlinedButton.icon(
                    onPressed: () => _discardIfDraft(observation),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Discard this draft'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showEvidence(Evidence evidence) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${evidence.role.label} · '
                '${evidence.isVideo ? 'video' : 'photo'}',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              Center(
                child: EvidenceThumb(
                  path: evidence.listImagePath,
                  size: 220,
                  radius: 12,
                  isVideo: evidence.isVideo,
                ),
              ),
              const SizedBox(height: 12),
              _FactRow(label: 'Original', value: evidence.originalPath),
              _FactRow(label: 'Size', value: formatBytes(evidence.sizeBytes)),
              if (evidence.width != null)
                _FactRow(
                  label: 'Pixels',
                  value: '${evidence.width}×${evidence.height}',
                ),
              if (evidence.durationMs != null)
                _FactRow(
                  label: 'Duration',
                  value:
                      '${(evidence.durationMs! / 1000).toStringAsFixed(1)} s',
                ),
              _FactRow(
                label: 'SHA-256',
                value: '${evidence.sha256.substring(0, 16)}…',
              ),
              _FactRow(label: 'Source', value: evidence.captureSource),
              _FactRow(
                label: 'Captured',
                value: evidence.capturedAt.toLocal().toString(),
              ),
              _FactRow(
                label: 'Upload',
                value: '${evidence.uploadState.label} · '
                    'attempts ${evidence.uploadAttempts}',
              ),
              if (evidence.lastError != null)
                _FactRow(label: 'Last error', value: evidence.lastError!),
              const SizedBox(height: 12),
              if (_verifying) ...<Widget>[
                const LinearProgressIndicator(),
                const SizedBox(height: 12),
              ],
              Row(
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      _verifyEvidence(evidence);
                    },
                    icon: const Icon(Icons.verified_outlined),
                    label: const Text('Verify integrity'),
                  ),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Identity, assessment and status of one report.
class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.observation});

  final Observation observation;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: observation.description.isEmpty
          ? categoryLabel(observation.category)
          : observation.description,
      icon: Icons.report_outlined,
      subtitle: 'Report ${observation.id}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              SeverityPill(level: observation.severity),
              PriorityPill(level: observation.priority),
              Pill(
                label: observation.status.label,
                color: const Color(0xFF3B9EFF),
                icon: Icons.flag_outlined,
              ),
              SyncPill(state: observation.syncState),
            ],
          ),
          const SizedBox(height: 10),
          _FactRow(
            label: 'Created',
            value: observation.createdAt.toLocal().toString(),
          ),
          _FactRow(
            label: 'Updated',
            value: observation.updatedAt.toLocal().toString(),
          ),
          _FactRow(
            label: 'Severity score',
            value: '${(observation.severityScore * 100).round()}/100',
          ),
          _FactRow(
            label: 'Priority score',
            value: '${(observation.priorityScore * 100).round()}/100',
          ),
          if (observation.aiConfidence != null)
            _FactRow(
              label: 'On-device AI',
              value: '${(observation.aiConfidence! * 100).round()}% · '
                  '${observation.aiModelVersion ?? 'model unknown'}',
            ),
          if (observation.aiSuggestedCategory != null)
            _FactRow(
              label: 'AI suggestion',
              value: categoryLabel(observation.aiSuggestedCategory!) +
                  (observation.categoryCorrectedByUser
                      ? ' (corrected by user)'
                      : ''),
            ),
          if (observation.serverId != null)
            _FactRow(label: 'Server id', value: observation.serverId!),
          if (observation.caseId != null)
            _FactRow(label: 'Case', value: observation.caseId!),
          if (observation.duplicateOfId != null)
            _FactRow(
              label: 'Possible duplicate of',
              value: observation.duplicateOfId!,
            ),
        ],
      ),
    );
  }
}

/// Honest sync panel: last message, attempts, and when the next retry runs.
class _SyncCard extends StatelessWidget {
  const _SyncCard({required this.observation, required this.onSync});

  final Observation observation;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final PortalServices services = PortalScope.of(context);
    final ThemeData theme = Theme.of(context);
    final DateTime? next = observation.nextAttemptAt;
    final String nextLabel = next == null
        ? 'no retry scheduled'
        : next.isAfter(DateTime.now())
            ? 'next retry in '
                '${next.difference(DateTime.now()).inSeconds}s'
            : 'retry due now';
    return SectionCard(
      title: 'Sync',
      icon: Icons.cloud_upload_outlined,
      trailing: services.repository.isSyncing
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _FactRow(
            label: 'State',
            value: '${observation.syncState.label} · '
                '${observation.attempts} attempt(s) · $nextLabel',
          ),
          if (services.repository.lastSyncMessage != null)
            _FactRow(
              label: 'Last sync message',
              value: services.repository.lastSyncMessage!,
            ),
          if (observation.lastError != null)
            _FactRow(label: 'Last error', value: observation.lastError!),
          if (!services.repository.backendConfigured)
            Text(
              'No backend is configured — reports stay on this device and can '
              'be exported from Settings.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: const Color(0xFFF76B15)),
            ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: services.repository.isSyncing ? null : onSync,
            icon: const Icon(Icons.sync),
            label: const Text('Sync now'),
          ),
        ],
      ),
    );
  }
}


/// One evidence cell: bounded thumbnail plus its real upload state.
class _EvidenceTile extends StatelessWidget {
  const _EvidenceTile({required this.evidence, required this.onTap});

  final Evidence evidence;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Stack(
            children: <Widget>[
              EvidenceThumb(
                path: evidence.listImagePath,
                size: 104,
                isVideo: evidence.isVideo,
              ),
              Positioned(
                right: 4,
                top: 4,
                child: Icon(
                  Icons.circle,
                  size: 10,
                  color: syncColor(evidence.uploadState),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            evidence.role.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
          Text(
            formatBytes(evidence.sizeBytes),
            style: TextStyle(fontSize: 10, color: Theme.of(context).hintColor),
          ),
        ],
      ),
    );
  }
}

/// Label / value line used for evidence and sync facts.
class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.hintColor),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

