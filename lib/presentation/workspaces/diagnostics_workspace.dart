import 'dart:io';
import 'package:flutter/material.dart';
import '../../camera/camera_service.dart';
import '../../config/app_theme.dart';
import '../../performance/telemetry_service.dart';
import '../../vision/models/model_metadata.dart';
import '../../vision/vision_service.dart';

/// Diagnostics & Hardware Telemetry Workspace.
class DiagnosticsWorkspace extends StatelessWidget {
  const DiagnosticsWorkspace({
    super.key,
    required this.cameraService,
    required this.visionService,
  });

  final CameraService cameraService;
  final VisionService visionService;

  @override
  Widget build(BuildContext context) {
    final isMobile = AppTheme.isMobile(context);
    final telemetry = TelemetryService.instance;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'System & Media Foundation Diagnostics',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Inspect on-device DirectShow capture pipelines, TFLite tensor memory, and frame latency.',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 20),

          // Diagnostic Cards Grid
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _DiagnosticCard(
                title: 'Capture Hardware',
                icon: Icons.camera_alt_outlined,
                items: [
                  _DiagItem('Platform', Platform.operatingSystem),
                  _DiagItem('Available Devices', '${cameraService.devices.length} detected'),
                  _DiagItem(
                    'Active Sensor',
                    cameraService.selectedDevice?.name ?? 'None',
                  ),
                  _DiagItem('Stream Status', cameraService.isRunning ? 'Active Streaming' : 'Standby / Dormant'),
                  _DiagItem('Sensor Frame Resolution', '${cameraService.width ?? 0} × ${cameraService.height ?? 0} px'),
                ],
              ),
              _DiagnosticCard(
                title: 'Edge AI Inference',
                icon: Icons.psychology_outlined,
                items: [
                  _DiagItem('Model Status', visionService.modelA.status == ModelStatus.ready ? 'Loaded & Ready' : 'Standby'),
                  _DiagItem('AI Engine Toggle', visionService.aiEnabled ? 'Enabled' : 'Disabled'),
                  _DiagItem('Target Inference FPS', '${visionService.targetInferenceFps} FPS'),
                  _DiagItem('Confidence Threshold', '${(visionService.confidenceThreshold * 100).toInt()}%'),
                  _DiagItem('Object Tracker', visionService.trackingEnabled ? 'IoU Centroid (Active)' : 'Disabled'),
                ],
              ),
              ListenableBuilder(
                listenable: telemetry,
                builder: (context, _) {
                  return _DiagnosticCard(
                    title: 'Live Telemetry & Metrics',
                    icon: Icons.speed_rounded,
                    items: [
                      _DiagItem('Effective Camera FPS', '${telemetry.currentFps.toStringAsFixed(1)} FPS'),
                      _DiagItem('AI Processing FPS', '${telemetry.currentInferenceFps.toStringAsFixed(1)} FPS'),
                      _DiagItem('Inference Latency', '${visionService.latencyMs.toStringAsFixed(1)} ms'),
                      _DiagItem('Total Frames Sampled', '${telemetry.totalFramesSampled}'),
                      _DiagItem('Dropped Overrun Frames', '${telemetry.droppedFrames}'),
                    ],
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DiagnosticCard extends StatelessWidget {
  const _DiagnosticCard({
    required this.title,
    required this.icon,
    required this.items,
  });

  final String title;
  final IconData icon;
  final List<_DiagItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 380,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.primary, size: 20),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppTheme.border),
          const SizedBox(height: 12),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(item.label, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  Text(
                    item.value,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagItem {
  final String label;
  final String value;
  const _DiagItem(this.label, this.value);
}
