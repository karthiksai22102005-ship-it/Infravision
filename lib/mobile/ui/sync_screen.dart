import 'package:flutter/material.dart';

import '../core/app_logger.dart';
import '../data/evidence_store.dart';
import '../models/observation.dart';
import 'portal_services.dart';
import 'report_detail_screen.dart';
import 'widgets.dart';

/// Sync queue, storage accounting and the diagnostics ring buffer (§31/§32,
/// §59/§60, §76). Every number shown here comes from a real measurement.
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  StorageBreakdown _usage = StorageBreakdown.empty;
  String? _message;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final PortalServices services = PortalScope.read(context);
    StorageBreakdown usage = StorageBreakdown.empty;
    try {
      usage = await services.evidenceStore.usage();
    } catch (_) {
      usage = StorageBreakdown.empty;
    }
    if (!mounted) return;
    setState(() {
      _usage = usage;
      _loading = false;
    });
  }

  Future<void> _clearDerivatives() async {
    final PortalServices services = PortalScope.of(context);
    final int removed =
        await services.evidenceStore.clearRegenerableDerivatives();
    await _load();
    if (!mounted) return;
    setState(() => _message =
        'Removed $removed regenerable thumbnails/derivatives. Originals and '
        'upload derivatives were left untouched.');
  }

  Future<void> _probeWrite() async {
    final PortalServices services = PortalScope.of(context);
    final bool writable = await services.evidenceStore.probeStorageWritable();
    if (!mounted) return;
    setState(() => _message = writable
        ? 'The evidence folder accepts new files.'
        : 'The evidence folder is NOT writable — reports cannot be saved.');
  }

  @override
  Widget build(BuildContext context) {
    final PortalServices services = PortalScope.of(context);
    final ThemeData theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(
        <Listenable>[services.repository, services.network],
      ),
      builder: (BuildContext context, Widget? child) {
        final List<Observation> pending = services.database.pendingSync();
        final int failed = services.repository.all
            .where((Observation o) => o.syncState == SyncState.failed)
            .length;
        return ListView(
          padding: const EdgeInsets.only(bottom: 28),
          children: <Widget>[
            SectionCard(
              title: 'Connection',
              icon: Icons.wifi_tethering,
              trailing: TextButton(
                onPressed: () {
                  services.refreshStatus();
                  _load();
                },
                child: const Text('Re-check'),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(services.network.label),
                  Text(
                    'Interface: ${services.network.connectionType} · checked '
                    '${services.network.lastChecked == null ? 'never' : timeAgo(services.network.lastChecked!)}',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (services.network.lastError != null)
                    Text(
                      services.network.lastError!,
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            SectionCard(
              title: 'Queue (${pending.length})',
              icon: Icons.cloud_upload_outlined,
              subtitle: services.repository.lastSyncMessage ??
                  'No sync has run yet',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (failed > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Pill(
                        label: '$failed failed — they keep retrying',
                        color: const Color(0xFFE5484D),
                      ),
                    ),
                  if (services.repository.isSyncing)
                    LinearProgressIndicator(
                      value: services.repository.uploadProgress > 0
                          ? services.repository.uploadProgress
                          : null,
                    ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: services.repository.isSyncing
                        ? null
                        : () => services.repository.syncNow(),
                    icon: const Icon(Icons.sync),
                    label: const Text('Sync now'),
                  ),
                  const SizedBox(height: 10),
                  if (pending.isEmpty)
                    Text(
                      'Nothing is waiting: everything on this device has been '
                      'accepted by the backend.',
                      style: theme.textTheme.bodySmall,
                    )
                  else
                    ...pending.take(15).map(_queueTile),
                ],
              ),
            ),
            SectionCard(
              title: 'Storage',
              icon: Icons.sd_storage_outlined,
              subtitle: _loading ? 'measuring…' : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _line('Originals', formatBytes(_usage.originalBytes)),
                  _line('Derivatives', formatBytes(_usage.derivativeBytes)),
                  _line('Database', formatBytes(_usage.databaseBytes)),
                  _line('Models', formatBytes(_usage.modelBytes)),
                  _line('Total', formatBytes(_usage.totalBytes)),
                  _line('Files', '${_usage.fileCount}'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: <Widget>[
                      OutlinedButton.icon(
                        onPressed: _clearDerivatives,
                        icon: const Icon(Icons.cleaning_services_outlined),
                        label: const Text('Free space'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _probeWrite,
                        icon: const Icon(Icons.drive_folder_upload_outlined),
                        label: const Text('Test write access'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: Text(_message!, style: theme.textTheme.bodySmall),
              ),
            SectionCard(
              title: 'Diagnostics',
              icon: Icons.bug_report_outlined,
              subtitle: '${AppLog.diagnostics.length} lines in memory',
              trailing: TextButton(
                onPressed: () => setState(AppLog.clear),
                child: const Text('Clear'),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: AppLog.diagnostics.reversed.take(40).map(
                  (String line) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Text(
                        line,
                        style: const TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                    );
                  },
                ).toList(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _queueTile(Observation o) {
    final DateTime? next = o.nextAttemptAt;
    final String retry = next == null
        ? 'due now'
        : next.isAfter(DateTime.now())
            ? 'next retry in ${next.difference(DateTime.now()).inSeconds}s'
            : 'due now';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: SyncPill(state: o.syncState, dense: true),
      title: Text(
        o.description.isEmpty ? o.id : o.description,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        'attempts ${o.attempts} · $retry'
        '${o.lastError == null ? '' : ' · ${o.lastError}'}',
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (BuildContext context) =>
              ReportDetailScreen(observationId: o.id),
        ),
      ),
    );
  }

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style:
                    TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
              ),
            ),
            Text(value, style: const TextStyle(fontSize: 12)),
          ],
        ),
      );
}
