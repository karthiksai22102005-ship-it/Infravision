import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../core/ml/pothole_detector.dart';

class DetectionOverlayScreen extends StatefulWidget {
  final String imagePath;
  const DetectionOverlayScreen({super.key, required this.imagePath});

  @override
  State<DetectionOverlayScreen> createState() => _DetectionOverlayScreenState();
}

class _DetectionOverlayScreenState extends State<DetectionOverlayScreen> {
  bool _loading = true;
  List<Detection> _detections = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _runInference();
  }

  Future<void> _runInference() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final st = context.read<AppState>();
    try {
      final results = await st.detector.detect(widget.imagePath);
      if (mounted) {
        setState(() {
          _detections = results;
          _loading = false;
        });
        if (results.isNotEmpty) {
          st.updateDraft((d) {
            d.aiDetections = results;
            d.categoryCode ??= 'pothole';
          });
        }
      }
    } catch (error, stack) {
      debugPrint('Pothole review inference failed: $error\n$stack');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = st.s('analysisFailed');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final s = st.s;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('AI Analysis Review'),
      ),
      body: Column(
        children: [
          // Banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: _detections.isNotEmpty
                ? const Color(0xFF1E3A2F)
                : const Color(0xFF2B2B2B),
            child: Row(
              children: [
                Icon(
                  _detections.isNotEmpty
                      ? Icons.auto_awesome
                      : Icons.info_outline,
                  color: _detections.isNotEmpty
                      ? const Color(0xFF43E9B2)
                      : Colors.white70,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _loading
                        ? 'Analyzing image for road defects...'
                        : _error != null
                            ? _error!
                            : _detections.isNotEmpty
                            ? '${_detections.length} Pothole(s) Detected (${(_detections.first.confidence * 100).toStringAsFixed(0)}% conf)'
                            : 'No potholes detected. Manual reporting is available.',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          // Image preview with overlay
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: Image.file(
                    File(widget.imagePath),
                    fit: BoxFit.contain,
                  ),
                ),
                if (!_loading && _detections.isNotEmpty)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return CustomPaint(
                        size: Size(constraints.maxWidth, constraints.maxHeight),
                        painter: _DetectionPainter(_detections),
                      );
                    },
                  ),
                if (_loading)
                  Container(
                    color: Colors.black38,
                    child: const Center(
                      child:
                          CircularProgressIndicator(color: Color(0xFF43E9B2)),
                    ),
                  ),
              ],
            ),
          ),
          // Action controls
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF181818),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _loading ? null : _runInference,
                      icon: const Icon(Icons.refresh),
                      label: Text(s('retryAi')),
                    ),
                  ),
                if (_detections.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Suggested Category: Pothole',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                        TextButton(
                          onPressed: () =>
                              Navigator.pushNamed(context, '/category'),
                          child: const Text('Change',
                              style: TextStyle(color: Color(0xFF43E9B2))),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white24),
                        ),
                        onPressed: () {
                          st.removePhotoPath(widget.imagePath).then((_) {
                            if (context.mounted) Navigator.pop(context);
                          });
                        },
                        child: Text(s('retake')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1A56DB),
                        ),
                        onPressed: _loading
                            ? null
                            : () {
                                Navigator.pushNamed(context, '/photos');
                              },
                        child: Text(s('next')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetectionPainter extends CustomPainter {
  final List<Detection> detections;
  _DetectionPainter(this.detections);

  @override
  void paint(Canvas canvas, Size size) {
    final boxPaint = Paint()
      ..color = const Color(0xFF43E9B2)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = const Color(0x3343E9B2)
      ..style = PaintingStyle.fill;

    const textStyle = TextStyle(
      color: Colors.black,
      fontSize: 11,
      fontWeight: FontWeight.bold,
    );

    for (final d in detections) {
      final rect = Rect.fromLTRB(
        d.x1 * size.width,
        d.y1 * size.height,
        d.x2 * size.width,
        d.y2 * size.height,
      );

      canvas.drawRect(rect, fillPaint);
      canvas.drawRect(rect, boxPaint);

      // Label background
      final labelText =
          '${d.label.toUpperCase()} ${(d.confidence * 100).toStringAsFixed(0)}%';
      final textSpan = TextSpan(text: labelText, style: textStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      final labelRect = Rect.fromLTWH(
        rect.left,
        max(0.0, rect.top - 20),
        textPainter.width + 8,
        20,
      );

      final bgPaint = Paint()..color = const Color(0xFF43E9B2);
      canvas.drawRRect(
          RRect.fromRectAndRadius(labelRect, const Radius.circular(4)),
          bgPaint);
      textPainter.paint(canvas, Offset(labelRect.left + 4, labelRect.top + 3));
    }
  }

  @override
  bool shouldRepaint(covariant _DetectionPainter oldDelegate) => true;
}
