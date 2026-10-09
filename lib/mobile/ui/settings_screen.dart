import 'dart:io';

import 'package:flutter/material.dart';

import '../config/mobile_config.dart';
import 'portal_services.dart';
import 'widgets.dart';

/// Backend, device capability, evidence vault and version information
/// (§62/§67/§78/§81). Nothing here pretends a value exists when it does not.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _url;
  final TextEditingController _token = TextEditingController();
  String _message = '';
  String _vaultPath = 'resolving…';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(
      text: PortalScope.read(context).repository.baseUrl,
    );
    _loadVaultPath();
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _loadVaultPath() async {
    final Directory root = await PortalScope.read(context).evidenceRoot();
    if (!mounted) return;
    setState(() => _vaultPath = root.path);
  }

  Future<void> _save() async {
    final PortalServices services = PortalScope.of(context);
    setState(() {
      _saving = true;
      _message = '';
    });
    try {
      await services.repository.setBackendUrl(_url.text);
      await services.repository.setAuthToken(_token.text.trim());
      await services.network.refresh(baseUrl: services.repository.baseUrl);
      if (!mounted) return;
      setState(() => _message = 'Saved. ${services.network.label}');
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() => _message = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final PortalServices services = PortalScope.of(context);
    final ThemeData theme = Theme.of(context);
    return ListenableBuilder(
      listenable: services.repository,
      builder: (BuildContext context, Widget? child) {
        return ListView(
          padding: const EdgeInsets.only(bottom: 28),
          children: <Widget>[
            SectionCard(
              title: 'Backend',
              icon: Icons.dns_outlined,
              subtitle: services.repository.backendConfigured
                  ? services.repository.baseUrl
                  : 'Not configured — reports stay on this device',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  TextField(
                    controller: _url,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Backend base URL',
                      hintText: 'https://api.example.org',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _token,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Bearer token (optional)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Saving…' : 'Save and test'),
                  ),
                  if (_message.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _message,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.hintColor),
                      ),
                    ),
                ],
              ),
            ),
            SectionCard(
              title: 'On-device analysis',
              icon: Icons.memory,
              subtitle: services.repository.analysis.isPrepared
                  ? 'Model ready'
                  : 'Model not ready',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _row(
                    'Model',
                    services.repository.analysis.modelVersion ??
                        'no model loaded',
                  ),
                  _row(
                    'Last inference',
                    services.repository.analysis.lastInferenceMs == 0
                        ? 'not run yet'
                        : '${services.repository.analysis.lastInferenceMs} ms',
                  ),
                  if (services.repository.analysis.problem != null)
                    _row(
                      'Problem',
                      services.repository.analysis.problem!,
                    ),
                  Text(
                    'Severity is calculated from the category, evidence and '
                    'measured image signals — never from an invented score.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor),
                  ),
                ],
              ),
            ),
            SectionCard(
              title: 'Device profile',
              icon: Icons.phone_android,
              subtitle: '${services.capabilities.profile.name} · '
                  '${services.capabilities.cpuCores} cores',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _row('Thermal', services.capabilities.thermal.name),
                  _row(
                    'Battery',
                    services.capabilities.batteryPercent == null
                        ? 'unknown'
                        : '${services.capabilities.batteryPercent}%'
                            '${services.capabilities.batterySaver ? ' (saver on)' : ''}',
                  ),
                  _row(
                    'Sync throttling',
                    services.capabilities.syncPausedForBattery
                        ? 'paused for battery'
                        : 'active',
                  ),
                  _row(
                    'AI input size',
                    '${services.capabilities.aiMaxDimension} px',
                  ),
                  _row(
                    'Thumbnail size',
                    '${services.capabilities.thumbnailDimension} px',
                  ),
                  _row(
                    'Parallel uploads',
                    '${services.capabilities.uploadConcurrency}',
                  ),
                  _row(
                    'Cache budget',
                    formatBytes(services.capabilities.cacheBudgetBytes),
                  ),
                ],
              ),
            ),
            SectionCard(
              title: 'Evidence vault',
              icon: Icons.lock_outline,
              child: SelectableText(_vaultPath, style: theme.textTheme.bodySmall),
            ),
            SectionCard(
              title: 'About',
              icon: Icons.info_outline,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _row('Version', MobileConfig.appVersionName),
                  _row('Build number', '${MobileConfig.appVersionCode}'),
                  _row('Build environment', MobileConfig.buildEnvironment),
                  _row('API version', '${MobileConfig.apiVersion}'),
                  _row(
                    'Compile-time API',
                    MobileConfig.compileTimeApiBaseUrl.isEmpty
                        ? 'not baked in'
                        : MobileConfig.compileTimeApiBaseUrl,
                  ),
                  _row('Observer id', services.repository.observerId),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 140,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).hintColor,
                ),
              ),
            ),
            Expanded(
              child: SelectableText(
                value,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      );
}
