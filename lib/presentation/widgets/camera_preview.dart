import 'package:flutter/material.dart';
import '../../camera/camera_service.dart';
import '../../vision/vision_service.dart';
import 'vision_overlay.dart';

enum CameraFraming {
  fit('Fit (100%)', 'Preserve original aspect ratio with letterboxing'),
  fill('Fill (Cover)', 'Expand video feed to fill viewport'),
  adaptive('Adaptive (Auto)', 'Auto-adjust to sensor aspect ratio (16:9 / 4:3)');

  const CameraFraming(this.label, this.description);
  final String label;
  final String description;
}

/// Clean, high-performance Camera Preview widget.
///
/// Features:
/// - Pure webcam video stream without distortion
/// - Digital Zoom (1.0x to 4.0x) with smooth scaling
/// - Framing modes (Fit, Fill, Adaptive)
/// - Optional YOLO bounding box overlay (Default = OFF for clean inspection)
class CameraPreview extends StatelessWidget {
  const CameraPreview({
    super.key,
    this.framing = CameraFraming.fit,
    this.zoomLevel = 1.0,
    this.onDoubleTapResetZoom,
  });

  final CameraFraming framing;
  final double zoomLevel;
  final VoidCallback? onDoubleTapResetZoom;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CameraService.instance,
      builder: (context, _) {
        final service = CameraService.instance;
        final textureId = service.textureId;
        final width = service.width;
        final height = service.height;

        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
            ),
            child: textureId == null || textureId == -1
                ? _PreviewPlaceholder(
                    isStarting: service.isStarting,
                    hasError: service.hasError,
                    message: service.lastError ??
                        (service.isStarting
                            ? 'Connecting to built-in camera…'
                            : 'Select a camera device and click Start Camera Stream'),
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      // 1. Digital Zoom + Framing Container
                      GestureDetector(
                        onDoubleTap: onDoubleTapResetZoom,
                        child: ClipRect(
                          child: Transform.scale(
                            scale: zoomLevel.clamp(1.0, 4.0),
                            child: _buildFramedTexture(textureId, width, height),
                          ),
                        ),
                      ),

                      // 2. Optional Vision Overlay (Active ONLY when OVERLAY == ON)
                      ListenableBuilder(
                        listenable: VisionService.instance,
                        builder: (context, _) {
                          final vision = VisionService.instance;
                          if (!vision.overlayEnabled) {
                            return const SizedBox.shrink();
                          }
                          return Stack(
                            children: [
                              const Positioned.fill(child: VisionOverlay()),

                              // Top Left: Live Ensemble Stream Pill
                              Positioned(
                                top: 14,
                                left: 14,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xCC0B1510),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0x6600E5A0)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 7,
                                        height: 7,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF00E5A0),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 7),
                                      const Text(
                                        'LIVE ENSEMBLE STREAM',
                                        style: TextStyle(
                                          color: Color(0xFF00E5A0),
                                          fontWeight: FontWeight.w800,
                                          fontSize: 10.5,
                                          letterSpacing: 0.6,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // Top Right: Live Telemetry Metrics Pill
                              Positioned(
                                top: 14,
                                right: 14,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xCC08120E),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.aspect_ratio_rounded, color: Colors.white70, size: 13),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${width ?? 1280}×${height ?? 720}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.videocam_rounded, color: Color(0xFF00E5A0), size: 13),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${service.measuredFps.toStringAsFixed(1)} FPS',
                                        style: const TextStyle(
                                          color: Color(0xFF00E5A0),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.psychology_rounded, color: Color(0xFF00B4D8), size: 13),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${vision.inferenceFps.toStringAsFixed(1)} AI-FPS',
                                        style: const TextStyle(
                                          color: Color(0xFF00B4D8),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.timer_outlined, color: Color(0xFFFFB703), size: 13),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${vision.latencyMs.toStringAsFixed(0)}ms',
                                        style: const TextStyle(
                                          color: Color(0xFFFFB703),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // Bottom Left: Active Tracks Badge
                              Positioned(
                                bottom: 14,
                                left: 14,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xCC08120E),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0x8800E5A0)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.sensors_rounded, color: Color(0xFF00E5A0), size: 14),
                                      const SizedBox(width: 6),
                                      Text(
                                        '${vision.trackedObjects.length} ACTIVE TRACKS',
                                        style: const TextStyle(
                                          color: Color(0xFF00E5A0),
                                          fontWeight: FontWeight.w800,
                                          fontSize: 11,
                                          letterSpacing: 0.5,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),

                      // 3. Zoom indicator badge if zoomed
                      if (zoomLevel > 1.05)
                        Positioned(
                          top: 48,
                          left: 14,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.zoom_in_rounded, color: Colors.cyanAccent, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  '${zoomLevel.toStringAsFixed(1)}x ZOOM',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _buildFramedTexture(int textureId, int? width, int? height) {
    final aspect = (width != null && height != null && height > 0) ? width / height : 16 / 9;

    switch (framing) {
      case CameraFraming.fill:
        return LayoutBuilder(
          builder: (context, constraints) {
            return SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: width?.toDouble() ?? 1280,
                  height: height?.toDouble() ?? 720,
                  child: Texture(textureId: textureId),
                ),
              ),
            );
          },
        );
      case CameraFraming.adaptive:
      case CameraFraming.fit:
        return Center(
          child: AspectRatio(
            aspectRatio: aspect,
            child: Texture(textureId: textureId),
          ),
        );
    }
  }
}

class _PreviewPlaceholder extends StatelessWidget {
  const _PreviewPlaceholder({
    required this.isStarting,
    required this.hasError,
    required this.message,
  });

  final bool isStarting;
  final bool hasError;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: hasError ? const Color(0xFF381515) : const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: hasError ? const Color(0xFFFF6B6B) : const Color(0xFF475569),
                  width: 1.2,
                ),
              ),
              child: isStarting
                  ? const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : Icon(
                      hasError ? Icons.videocam_off_rounded : Icons.videocam_outlined,
                      color: hasError ? const Color(0xFFFF8E8E) : Colors.white70,
                      size: 28,
                    ),
            ),
            const SizedBox(height: 14),
            Text(
              isStarting
                  ? 'Initializing camera stream…'
                  : (hasError ? 'Camera access issue' : 'Camera Standby (Hardware Dormant)'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: hasError ? const Color(0xFFFFB5B5) : Colors.white54,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
