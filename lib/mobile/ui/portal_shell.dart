import 'dart:async';

import 'package:flutter/material.dart';

import '../services/mobile_camera_service.dart';
import 'capture_screen.dart';
import 'home_screen.dart';
import 'portal_services.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'sync_screen.dart';

/// Navigation host: Home / Reports / Capture / Sync / Settings plus the always
/// visible connection + queue banner (§31, §52).
class PortalShell extends StatefulWidget {
  const PortalShell({super.key});

  @override
  State<PortalShell> createState() => _PortalShellState();
}

class _PortalShellState extends State<PortalShell>
    with WidgetsBindingObserver {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _refreshStatus() {
    // PortalScope.of() registers a build dependency and is illegal outside
    // build(); a lifecycle callback must use the non-registering read().
    if (!mounted) return;
    unawaited(PortalScope.read(context).refreshStatus());
  }

  /// The camera is an expensive, battery-hungry, process-wide singleton. When
  /// the user leaves the Capture tab it must be released immediately, otherwise
  /// the preview stays alive behind the other tabs and drains the battery (§57).
  void _open(int index) {
    if (index == _index) return;
    final bool leavingCapture = _index == 2;
    setState(() => _index = index);
    if (leavingCapture) {
      unawaited(MobileCameraService.instance.stop());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-check connectivity on resume so queued work retries automatically.
      _refreshStatus();
      return;
    }
    // Backgrounded: hand the camera and GPS back to the OS immediately.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(MobileCameraService.instance.stop());
      if (mounted) {
        unawaited(PortalScope.read(context).location.stopLiveTracking());
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: <Widget>[
          StatusBanner(onOpenSync: () => _open(3)),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: <Widget>[
                HomeScreen(onOpenTab: _open),
                const ReportsScreen(),
                const CaptureScreen(),
                const SyncScreen(),
                const SettingsScreen(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _open,
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt),
            label: 'Reports',
          ),
          NavigationDestination(
            icon: Icon(Icons.photo_camera_outlined),
            selectedIcon: Icon(Icons.photo_camera),
            label: 'Capture',
          ),
          NavigationDestination(
            icon: Icon(Icons.cloud_upload_outlined),
            selectedIcon: Icon(Icons.cloud_sync_outlined),
            label: 'Sync',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

/// Thin strip that always tells the truth about connectivity, queue depth and
/// on-device AI availability.
class StatusBanner extends StatelessWidget {
  const StatusBanner({super.key, required this.onOpenSync});

  final VoidCallback onOpenSync;

  @override
  Widget build(BuildContext context) {
    final PortalServices services = PortalScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(
        <Listenable>[services.repository, services.network],
      ),
      builder: (BuildContext context, Widget? child) {
        final bool online = services.network.deviceConnected;
        final bool backend = services.network.backendReachable;
        final int pending = services.repository.pendingCount;
        final bool syncing = services.repository.isSyncing;
        final Color color = backend
            ? const Color(0xFF46A758)
            : online
                ? const Color(0xFFF76B15)
                : const Color(0xFFE5484D);
        final String text = backend
            ? 'Backend reachable'
            : online
                ? 'Offline — backend unreachable'
                : 'Offline — no network';
        return Material(
          color: color.withValues(alpha: 0.12),
          child: InkWell(
            onTap: onOpenSync,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              child: Row(
                children: <Widget>[
                  Icon(Icons.circle, size: 9, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      text,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (syncing)
                    const Row(
                      children: <Widget>[
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 6),
                        Text('Syncing', style: TextStyle(fontSize: 12)),
                      ],
                    )
                  else if (pending > 0)
                    Text(
                      '$pending pending',
                      style: const TextStyle(fontSize: 12),
                    ),
                  const Icon(
                    Icons.chevron_right,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
