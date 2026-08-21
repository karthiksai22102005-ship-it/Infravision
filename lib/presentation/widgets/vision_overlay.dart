import 'package:flutter/material.dart';
import '../../tracking/multi_object_tracker.dart';
import '../../vision/vision_service.dart';

/// Level-2 HUD Overlay rendering unified bounding boxes, persistent Track IDs,
/// multi-model agreement badges, and target focus reticles.
class VisionOverlay extends StatelessWidget {
  const VisionOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: VisionService.instance,
      builder: (context, _) {
        final service = VisionService.instance;
        if (!service.aiEnabled) return const SizedBox.shrink();

        final trackedObjects = service.trackedObjects;

        return CustomPaint(
          painter: _Level2HudPainter(
            trackedObjects: trackedObjects,
            showSaliency: service.showSaliency,
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _Level2HudPainter extends CustomPainter {
  _Level2HudPainter({
    required this.trackedObjects,
    required this.showSaliency,
  });

  final List<MultiTrackObject> trackedObjects;
  final bool showSaliency;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    for (final track in trackedObjects) {
      _drawTrackedObject(canvas, size, track);
    }
  }

  void _drawTrackedObject(Canvas canvas, Size size, MultiTrackObject track) {
    final left = track.box.left * size.width;
    final top = track.box.top * size.height;
    final right = track.box.right * size.width;
    final bottom = track.box.bottom * size.height;
    final width = right - left;
    final height = bottom - top;

    if (width <= 10 || height <= 10) return;

    final primaryColor = Color(track.colorHex);
    final rect = Rect.fromLTRB(left, top, right, bottom);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(16));

    // 1. Soft glow around bounding box
    final glowPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 4.0);
    canvas.drawRRect(rrect, glowPaint);

    // 2. Smooth rounded focus border
    final boxPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRRect(rrect, boxPaint);

    // 3. Semi-transparent fill
    final fillPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.05)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rrect, fillPaint);

    // 4. Center target dot
    final cx = (left + right) / 2.0;
    final cy = (top + bottom) / 2.0;
    final reticlePaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    const reticleSize = 5.0;
    canvas.drawLine(
        Offset(cx - reticleSize, cy), Offset(cx + reticleSize, cy), reticlePaint);
    canvas.drawLine(
        Offset(cx, cy - reticleSize), Offset(cx, cy + reticleSize), reticlePaint);
    canvas.drawCircle(
      Offset(cx, cy),
      2.0,
      Paint()..color = primaryColor..style = PaintingStyle.fill,
    );

    // 5. Floating Header Badge with Track ID, Class, Confidence & Model Agreement
    final labelText =
        '${track.displayId}  ${track.className.toUpperCase()} ${(track.confidence * 100).toInt()}%';
    final agreementText = '• ${track.agreementBadge} models';

    _drawBadge(canvas, left, top - 26.0, labelText, agreementText, primaryColor);
  }

  void _drawBadge(Canvas canvas, double x, double y, String labelText,
      String agreementText, Color color) {
    const mainStyle = TextStyle(
      color: Colors.white,
      fontSize: 11.0,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.6,
    );

    const agreementStyle = TextStyle(
      color: Color(0xFF78F4B5),
      fontSize: 10.0,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.4,
    );

    final textSpan = TextSpan(children: [
      TextSpan(text: labelText, style: mainStyle),
      const TextSpan(text: '  '),
      TextSpan(text: agreementText, style: agreementStyle),
    ]);

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    final badgeWidth = textPainter.width + 18.0;
    const badgeHeight = 22.0;
    final badgeY = y < 4 ? y + 28 : y;

    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, badgeY, badgeWidth, badgeHeight),
      const Radius.circular(6.0),
    );

    // Background
    canvas.drawRRect(
      badgeRect,
      Paint()..color = const Color(0xF208120E)..style = PaintingStyle.fill,
    );

    // Border
    canvas.drawRRect(
      badgeRect,
      Paint()
        ..color = color.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Left accent bar
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, badgeY, 3.5, badgeHeight),
        const Radius.circular(2.0),
      ),
      Paint()..color = color..style = PaintingStyle.fill,
    );

    textPainter.paint(canvas, Offset(x + 9.0, badgeY + 3.0));
  }

  @override
  bool shouldRepaint(covariant _Level2HudPainter oldDelegate) {
    return true;
  }
}
