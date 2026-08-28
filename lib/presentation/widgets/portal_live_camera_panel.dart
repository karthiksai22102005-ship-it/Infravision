import 'dart:async';
import 'package:flutter/material.dart';
import '../../camera/camera_service.dart';
import '../../config/app_theme.dart';
import '../../performance/telemetry_service.dart';
import '../../vision/vision_service.dart';
import 'camera_preview.dart';

/// Reusable live webcam + AI overlay panel for field portals (desktop).
class PortalLiveCameraPanel extends StatefulWidget {
  const PortalLiveCameraPanel({
    super.key,
    this.height = 300,
    this.showOverlay = true,
    this.onSnapshotPath,
    this.accentColor = AppTheme.cyan,
  });

  final double height;
  final bool showOverlay;
  final ValueChanged<String>? onSnapshotPath;
  final Color accentColor;

  @override
  State<PortalLiveCameraPanel> createState() => _PortalLiveCameraPanelState();
}

class _PortalLiveCameraPanelState extends State<PortalLiveCameraPanel> {
  bool _ready = false;
  String? _lastSnapshot;

  @override
  void initState() {
    super.initState();
    unawaited(_bootCamera());
  }

  Future<void> _bootCamera() async {
    final camera = CameraService.instance;
    final vision = VisionService.instance;

    await camera.enumerateCameras();
    if (camera.devices.isNotEmpty) {
      camera.selectDevice(0);
    }
    await camera.startCamera();

    vision.setAiEnabled(true);
    vision.setOverlayEnabled(widget.showOverlay);
    if (camera.isRunning) {
      await vision.start();
    }

    if (mounted) setState(() => _ready = true);
  }

  Future<void> _capture() async {
    final path = await VisionService.instance.takeSnapshot();
    if (path == null || !mounted) return;
    setState(() => _lastSnapshot = path);
    widget.onSnapshotPath?.call(path);
  }

  @override
  void dispose() {
    VisionService.instance.stop();
    unawaited(CameraService.instance.stopCamera());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: widget.height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.border),
                borderRadius: BorderRadius.circular(16),
              ),
              child: _ready
                  ? const CameraPreview(framing: CameraFraming.fit)
                  : const Center(
                      child: CircularProgressIndicator(color: AppTheme.cyan, strokeWidth: 2),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.bgSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Text(
                  'AI ${TelemetryService.instance.currentInferenceFps.toStringAsFixed(1)} FPS • ${TelemetryService.instance.averageLatencyMs.toStringAsFixed(1)} ms',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.success,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: widget.accentColor),
              onPressed: _capture,
              icon: const Icon(Icons.photo_camera_rounded, size: 16),
              label: const Text('Capture Frame'),
            ),
          ],
        ),
        if (_lastSnapshot != null) ...[
          const SizedBox(height: 6),
          Text(
            'Last capture: $_lastSnapshot',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 9, color: AppTheme.textMuted, fontFamily: 'monospace'),
          ),
        ],
      ],
    );
  }
}
