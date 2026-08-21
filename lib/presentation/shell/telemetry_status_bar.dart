import 'package:flutter/material.dart';
import '../../camera/camera_service.dart';
import '../../config/app_theme.dart';
import '../../performance/telemetry_service.dart';
import '../../vision/vision_service.dart';

/// Bottom status & quick toggle telemetry bar.
class TelemetryStatusBar extends StatelessWidget {
  const TelemetryStatusBar({
    super.key,
    required this.cameraService,
    required this.visionService,
    required this.onToggleCamera,
    required this.onSnapshot,
  });

  final CameraService cameraService;
  final VisionService visionService;
  final VoidCallback onToggleCamera;
  final VoidCallback onSnapshot;

  @override
  Widget build(BuildContext context) {
    final telemetry = TelemetryService.instance;

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF0B1120),
        border: Border(top: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _StatusToggle(
              label: 'CAMERA',
              isOn: cameraService.isRunning,
              onTap: onToggleCamera,
            ),
            const SizedBox(width: 14),
            _StatusToggle(
              label: 'AI VISION',
              isOn: visionService.aiEnabled,
              onTap: () => visionService.setAiEnabled(!visionService.aiEnabled),
            ),
            const SizedBox(width: 14),
            _StatusToggle(
              label: 'OVERLAY',
              isOn: visionService.overlayEnabled,
              onTap: () => visionService.setOverlayEnabled(!visionService.overlayEnabled),
            ),
            const SizedBox(width: 14),
            _StatusToggle(
              label: 'TRACKER',
              isOn: visionService.trackingEnabled,
              onTap: () => visionService.setTrackingEnabled(!visionService.trackingEnabled),
            ),
            const SizedBox(width: 16),
            Container(width: 1, height: 16, color: AppTheme.border),
            const SizedBox(width: 16),
            Text(
              'Resolution: ${cameraService.width ?? 0}×${cameraService.height ?? 0}',
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppTheme.textSecondary),
            ),
            const SizedBox(width: 14),
            ListenableBuilder(
              listenable: telemetry,
              builder: (context, _) {
                final latency = visionService.latencyMs > 0 ? visionService.latencyMs : telemetry.averageLatencyMs;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Latency: ${latency.toStringAsFixed(1)} ms',
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppTheme.textSecondary),
                    ),
                    if (telemetry.currentFps > 0) ...[
                      const SizedBox(width: 14),
                      Text(
                        'FPS: ${telemetry.currentFps.toStringAsFixed(1)}',
                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppTheme.primary),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusToggle extends StatelessWidget {
  const _StatusToggle({
    required this.label,
    required this.isOn,
    required this.onTap,
  });

  final String label;
  final bool isOn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isOn ? AppTheme.success : AppTheme.textMuted,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$label: ${isOn ? "ON" : "OFF"}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isOn ? AppTheme.textPrimary : AppTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
