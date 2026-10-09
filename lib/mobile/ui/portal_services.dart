import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../config/mobile_config.dart';
import '../core/app_logger.dart';
import '../data/evidence_store.dart';
import '../data/local_database.dart';
import '../repositories/observation_repository.dart';
import '../services/analysis_service.dart';
import '../services/device_capability_service.dart';
import '../services/image_pipeline_service.dart';
import '../services/location_service.dart';
import '../services/mobile_camera_service.dart';
import '../services/network_service.dart';

/// Composition root for the Observation Portal (§79).
///
/// Every long-lived service is constructed exactly once here and handed to the
/// widget tree through [PortalScope]. Widgets never construct services and
/// never talk to HTTP directly.
class PortalServices {
  PortalServices({
    required this.repository,
    required this.location,
    required this.camera,
    required this.network,
    required this.capabilities,
    required this.database,
    required this.evidenceStore,
  }) {
    _networkListener = () {
      if (network.backendReachable &&
          repository.pendingCount > 0 &&
          !repository.isSyncing) {
        _scheduleAutoSync();
      }
    };
    network.addListener(_networkListener);
  }

  final ObservationRepository repository;
  final LocationService location;
  final MobileCameraService camera;
  final NetworkService network;
  final DeviceCapabilityService capabilities;
  final LocalDatabase database;
  final EvidenceStore evidenceStore;

  late final VoidCallback _networkListener;
  Timer? _autoSyncTimer;

  /// Builds the real, fully-wired service graph. Safe to call once at startup.
  static Future<PortalServices> bootstrap() async {
    final Stopwatch watch = Stopwatch()..start();

    Directory root;
    try {
      final Directory base = await getApplicationDocumentsDirectory();
      root = Directory('${base.path}/infravision_observation');
    } catch (e) {
      AppLog.e('Bootstrap', 'path_provider unavailable: $e');
      root = Directory('${Directory.systemTemp.path}/infravision_observation');
    }
    await root.create(recursive: true);

    final EvidenceStore store = EvidenceStore(rootDirectory: root);
    final LocalDatabase database = LocalDatabase(rootDirectory: root);
    final NetworkService network = NetworkService();
    final DeviceCapabilityService capabilities = DeviceCapabilityService();
    final AnalysisService analysis = AnalysisService();
    final ImagePipelineService pipeline = ImagePipelineService.instance;

    await capabilities.initialize();

    final ObservationRepository repository = ObservationRepository(
      database: database,
      evidenceStore: store,
      network: network,
      capabilities: capabilities,
      analysis: analysis,
      pipeline: pipeline,
    );
    await repository.initialize();

    AppLog.i(
      'Bootstrap',
      'Portal ready in ${watch.elapsedMilliseconds} ms '
      '(${database.observations.length} reports, '
      '${database.totalEvidenceCount} evidence items)',
    );

    return PortalServices(
      repository: repository,
      location: LocationService(),
      camera: MobileCameraService.instance,
      network: network,
      capabilities: capabilities,
      database: database,
      evidenceStore: store,
    );
  }

  /// Resolves the evidence vault root (needed by screens that show paths).
  Future<Directory> evidenceRoot() => evidenceStore.root();

  /// Sync as soon as the backend becomes reachable again (§31) — debounced so
  /// a flaky connection cannot start several passes.
  void _scheduleAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer(const Duration(seconds: 4), () {
      if (repository.isSyncing || repository.pendingCount == 0) return;
      if (!repository.backendConfigured) return;
      unawaited(repository.syncNow());
    });
  }

  /// Re-checks connectivity and device profile (called on resume/refresh).
  Future<void> refreshStatus() async {
    await capabilities.refresh();
    await network.refresh(baseUrl: repository.baseUrl);
    if (network.backendReachable && repository.pendingCount > 0) {
      _scheduleAutoSync();
    }
  }

  /// Releases resources. Process-wide singletons (camera) are only *stopped* —
  /// disposing them would poison every later user of the same instance.
  void shutdown() {
    _autoSyncTimer?.cancel();
    network.removeListener(_networkListener);
    repository.dispose();
    location.dispose();
    unawaited(camera.stop());
  }
}

/// Reads the current build flavour/version for the About panel (§81).
String buildEnvironmentLabel() => MobileConfig.buildEnvironment;

/// Makes [PortalServices] available to the whole widget tree.
class PortalScope extends InheritedWidget {
  const PortalScope({
    super.key,
    required this.services,
    required super.child,
  });

  final PortalServices services;

  /// Dependency-registering access for `build()` methods: widgets rebuilt when
  /// the scope changes.
  static PortalServices of(BuildContext context) {
    final PortalScope? scope =
        context.dependOnInheritedWidgetOfExactType<PortalScope>();
    assert(scope != null, 'PortalScope is missing above this widget');
    return scope!.services;
  }

  /// Non-registering access for `initState()`/`dispose()`, where calling
  /// [of] would be illegal because the dependency is not yet established.
  static PortalServices read(BuildContext context) {
    final PortalScope? scope =
        context.getInheritedWidgetOfExactType<PortalScope>();
    assert(scope != null, 'PortalScope is missing above this widget');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(PortalScope oldWidget) =>
      oldWidget.services != services;
}
