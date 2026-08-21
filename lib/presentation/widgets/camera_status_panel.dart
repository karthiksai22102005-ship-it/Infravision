import 'package:flutter/material.dart';
import 'package:infravision_camera/infravision_camera.dart';

import '../../camera/camera_service.dart';
import '../../config/app_theme.dart';

/// Compact, live camera diagnostics for the side/control panel.
class CameraStatusPanel extends StatelessWidget {
  const CameraStatusPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CameraService.instance,
      builder: (context, _) {
        final service = CameraService.instance;
        final state = service.state;
        final isLive = state == CameraState.running;
        final stateLabel = switch (state) {
          CameraState.stopped => 'STANDBY',
          CameraState.starting => 'INITIALIZING',
          CameraState.running => 'STREAM ACTIVE',
          CameraState.stopping => 'STOPPING',
          CameraState.error => 'FAULT',
        };
        final stateColor = switch (state) {
          CameraState.running => AppTheme.success,
          CameraState.starting || CameraState.stopping => AppTheme.warning,
          CameraState.error => AppTheme.error,
          CameraState.stopped => AppTheme.textMuted,
        };

        final resolution = service.width == null || service.height == null
            ? '—'
            : '${service.width} × ${service.height}';

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.bgSurfaceSubtle,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: stateColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    stateLabel,
                    style: TextStyle(
                      color: stateColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                service.selectedDevice?.name ?? 'No camera selected',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _Metric(label: 'RESOLUTION', value: resolution),
                  _Metric(
                    label: 'FRAME RATE',
                    value: isLive ? '${service.measuredFps.toStringAsFixed(1)} FPS' : '—',
                    accent: isLive,
                  ),
                  _Metric(
                    label: 'FRAMES',
                    value: isLive ? service.framesReceived.toString() : '—',
                    accent: isLive,
                  ),
                  _Metric(label: 'FORMAT', value: service.pixelFormat ?? '—'),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.accent = false,
  });

  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 105,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 9,
              letterSpacing: 0.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent ? AppTheme.primary : AppTheme.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}