import 'package:flutter/material.dart';

import '../models/observation.dart';
import 'capture_screen.dart';
import 'portal_services.dart';
import 'report_detail_screen.dart';
import 'widgets.dart';

/// Field-crew landing screen: state at a glance, one-tap new report, and the
/// unfinished drafts this device still owns (§36, §52).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onOpenTab});

  final ValueChanged<int> onOpenTab;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _storageBytes = 0;
  bool _loadingStorage = true;

  @override
  void initState() {
    super.initState();
    _loadStorage();
  }

  Future<void> _loadStorage() async {
    final PortalServices services = PortalScope.read(context);
    int bytes = 0;
    try {
      bytes = (await services.evidenceStore.usage()).totalBytes;
    } catch (_) {
      bytes = 0;
    }
    if (!mounted) return;
    setState(() {
      _storageBytes = bytes;
      _loadingStorage = false;
    });
  }

  Future<void> _resumeDraft(String observationId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            CaptureScreen(observationId: observationId),
      ),
    );
    if (!mounted) return;
    _loadStorage();
  }

  void _openDetail(Observation observation) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            ReportDetailScreen(observationId: observation.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final PortalServices services = PortalScope.of(context);
    final ThemeData theme = Theme.of(context);
    return ListenableBuilder(
      listenable: services.repository,
      builder: (BuildContext context, Widget? child) {
        final List<Observation> drafts = services.repository.drafts;
        final List<Observation> recent =
            services.database.pageObservations(limit: 5).items;
        final int pending = services.repository.pendingCount;
        final int failed = services.repository.all
            .where((Observation o) => o.syncState == SyncState.failed)
            .length;
        return RefreshIndicator(
          onRefresh: () async {
            _loadStorage();
            await services.refreshStatus();
          },
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: <Widget>[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Observation Portal',
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '${services.capabilities.profile.name} profile · '
                      '${services.database.observations.length} reports on device',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.hintColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                    ),
                    onPressed: () => widget.onOpenTab(2),
                    icon: const Icon(Icons.add_a_photo),
                    label: const Text(
                      'New pothole report',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
              _StatRow(
                pending: pending,
                failed: failed,
                total: services.database.observations.length,
                storageLabel: _loadingStorage
                    ? '…'
                    : formatBytes(_storageBytes),
              ),
              if (drafts.isNotEmpty)
                SectionCard(
                  title: 'Unfinished drafts',
                  icon: Icons.edit_note,
                  subtitle: 'Saved on this device — finish and submit them',
                  child: Column(
                    children: drafts.map(_draftTile).toList(),
                  ),
                ),
              if (pending > 0 || failed > 0)
                Card(
                  margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                  child: ListTile(
                    leading: Icon(
                      failed > 0 ? Icons.error_outline : Icons.cloud_upload,
                      color: failed > 0 ? const Color(0xFFE5484D) : null,
                    ),
                    title: Text(
                      failed > 0
                          ? '$failed failed · $pending waiting to sync'
                          : '$pending waiting to sync',
                    ),
                    subtitle: const Text(
                      'They upload automatically once the backend is reachable',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => widget.onOpenTab(3),
                  ),
                ),
              SectionCard(
                title: 'Recent reports',
                icon: Icons.history,
                child: recent.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('No reports yet. Capture one to begin.'),
                      )
                    : Column(
                        children: recent.map(_recentTile).toList(),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _draftTile(Observation o) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.edit_note),
        title: Text(
          o.description.isEmpty ? '${o.category} draft' : o.description,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${o.evidenceIds.length} evidence · ${timeAgo(o.updatedAt)}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _resumeDraft(o.id),
      );

  Widget _recentTile(Observation o) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.location_on_outlined),
        title: Text(
          o.description.isEmpty ? o.category : o.description,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${timeAgo(o.createdAt)} · ${o.evidenceIds.length} evidence',
        ),
        trailing: PriorityPill(level: o.priority, dense: true),
        onTap: () => _openDetail(o),
      );
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.pending,
    required this.failed,
    required this.total,
    required this.storageLabel,
  });

  final int pending;
  final int failed;
  final int total;
  final String storageLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: <Widget>[
          _StatCell(label: 'Reports', value: '$total'),
          const SizedBox(width: 8),
          _StatCell(label: 'Pending', value: '$pending'),
          const SizedBox(width: 8),
          _StatCell(label: 'Failed', value: '$failed'),
          const SizedBox(width: 8),
          _StatCell(label: 'Storage', value: storageLabel),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          child: Column(
            children: <Widget>[
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).hintColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
