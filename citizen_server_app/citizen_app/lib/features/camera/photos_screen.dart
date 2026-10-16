import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../core/config/app_config.dart';
import '../../core/network/models.dart';
import '../../core/vision/defect_detector.dart';
import '../../core/widgets/common.dart';

class PhotosScreen extends StatefulWidget {
  const PhotosScreen({super.key});

  @override
  State<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends State<PhotosScreen> {
  late final Future<CitizenDefectDetector> _detector =
      CitizenDefectDetector.load();
  final Set<String> _analyzing = {};
  final Set<String> _analysisErrors = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _analyzeUncached());
  }

  @override
  void dispose() {
    _detector.then((model) => model.close()).catchError((Object _) {});
    super.dispose();
  }

  Future<void> _analyzeUncached() async {
    if (!mounted) return;
    final state = context.read<AppState>();
    for (final path in List<String>.from(state.draft.photos)) {
      final saved = state.draft.photoAnalyses[path];
      if (saved?['modelVersion'] == CitizenDefectDetector.modelVersion) {
        continue;
      }
      await _analyze(path);
    }
  }

  Future<void> _analyze(String path) async {
    if (_analyzing.contains(path) || !mounted) return;
    setState(() {
      _analyzing.add(path);
      _analysisErrors.remove(path);
    });
    try {
      final detector = await _detector;
      final analysis = await detector.analyzeFile(path);
      if (!mounted) return;
      await context.read<AppState>().savePhotoAnalysis(
            path,
            analysis.toJson(),
          );
    } catch (error) {
      debugPrint('On-device pothole analysis failed: $error');
      if (mounted) setState(() => _analysisErrors.add(path));
    } finally {
      if (mounted) setState(() => _analyzing.remove(path));
    }
  }

  Future<void> _pickMore(AppState state) async {
    final files = await ImagePicker().pickMultiImage(
      limit: AppConfig.maxPhotos,
      imageQuality: 90,
    );
    for (final file in files) {
      try {
        await state.addPhoto(file.path);
        if (mounted) await _analyze(state.draft.photos.last);
      } on ApiException catch (error) {
        if (mounted) showSnack(context, error.message);
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = state.s;
    final photos = state.draft.photos;
    return Scaffold(
      appBar: StepHeader(3, s('addPhotos')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: photos.isEmpty
                  ? StateMessage(
                      icon: Icons.photo_camera_outlined,
                      text: s('noPhotos'),
                    )
                  : ListView.separated(
                      itemCount: photos.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final path = photos[index];
                        final raw = state.draft.photoAnalyses[path];
                        final analysis = raw == null
                            ? null
                            : PhotoDefectAnalysis.fromJson(raw);
                        final error = _analysisErrors.contains(path);
                        final busy = _analyzing.contains(path);
                        return Card(
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                height: 230,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.file(File(path), fit: BoxFit.contain),
                                    if (analysis != null &&
                                        analysis.detections.isNotEmpty)
                                      CustomPaint(
                                        painter: _DetectionPainter(analysis),
                                      ),
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: IconButton.filledTonal(
                                        tooltip: 'Remove photo',
                                        onPressed: () =>
                                            state.removePhoto(index),
                                        icon: const Icon(Icons.close),
                                      ),
                                    ),
                                    Positioned(
                                      left: 10,
                                      top: 10,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: Colors.black
                                              .withValues(alpha: 0.68),
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 5),
                                          child: Text(
                                            analysis == null
                                                ? 'Original photo'
                                                : 'Local AI preview',
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(14, 10, 14, 14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (busy) ...[
                                      const LinearProgressIndicator(),
                                      const SizedBox(height: 8),
                                      Text(s('analyzingPhoto')),
                                    ] else if (error ||
                                        analysis?.hasError == true) ...[
                                      Text(s('analysisFailed'),
                                          style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .error)),
                                      TextButton.icon(
                                        onPressed: () => _analyze(path),
                                        icon: const Icon(Icons.refresh),
                                        label: Text(s('retryAi')),
                                      ),
                                    ] else if (analysis == null) ...[
                                      Text(s('analysisNotRun')),
                                      TextButton.icon(
                                        onPressed: () => _analyze(path),
                                        icon: const Icon(Icons.auto_awesome),
                                        label: Text(s('analyzeDevice')),
                                      ),
                                    ] else if (analysis.detections.isEmpty) ...[
                                      Text(s('noDefectDetected')),
                                      _analysisMeta(analysis),
                                    ] else ...[
                                      Text(
                                        '${analysis.detections.length} detection${analysis.detections.length == 1 ? '' : 's'} — review the suggestions below',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700),
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 7,
                                        runSpacing: 7,
                                        children: [
                                          for (final detection
                                              in analysis.detections)
                                            Chip(
                                              avatar: const Icon(
                                                  Icons.auto_awesome,
                                                  size: 16),
                                              label: Text(
                                                  '${detection.label} · ${(detection.confidence * 100).toStringAsFixed(0)}%'),
                                            ),
                                        ],
                                      ),
                                      _analysisMeta(analysis),
                                      TextButton.icon(
                                        onPressed: () => _analyze(path),
                                        icon: const Icon(Icons.refresh),
                                        label: Text(s('analyzeAgain')),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 4),
            Text(
                '${photos.length} ${s('photosAdded')} (Max ${AppConfig.maxPhotos})',
                style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(s('retake')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: photos.length >= AppConfig.maxPhotos
                        ? null
                        : () => _pickMore(state),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(s('addPhotos')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.arrow_forward),
                label: Text(s('next')),
                onPressed: () => Navigator.pushNamed(context, '/review'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _analysisMeta(PhotoDefectAnalysis analysis) => Padding(
        padding: const EdgeInsets.only(top: 7),
        child: Text(
          'On-device ${analysis.modelVersion} · ${analysis.inferenceMs} ms',
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
      );
}

class _DetectionPainter extends CustomPainter {
  const _DetectionPainter(this.analysis);
  final PhotoDefectAnalysis analysis;

  @override
  void paint(Canvas canvas, Size size) {
    if (analysis.width <= 0 || analysis.height <= 0) return;
    final imageSize =
        Size(analysis.width.toDouble(), analysis.height.toDouble());
    final fitted = applyBoxFit(BoxFit.contain, imageSize, size);
    final rect =
        Alignment.center.inscribe(fitted.destination, Offset.zero & size);
    final paint = Paint()
      ..color = const Color(0xFF00E676)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    final labelPaint = Paint()..color = const Color(0xCC071326);
    for (final detection in analysis.detections) {
      final box = Rect.fromLTRB(
        rect.left + detection.left * rect.width,
        rect.top + detection.top * rect.height,
        rect.left + detection.right * rect.width,
        rect.top + detection.bottom * rect.height,
      );
      canvas.drawRect(box, paint);
      final text =
          '${detection.label} ${(detection.confidence * 100).round()}%';
      final painter = TextPainter(
        text: TextSpan(
            text: text,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width - 12);
      final tag = Rect.fromLTWH(
          box.left,
          (box.top - painter.height - 6).clamp(0, size.height),
          painter.width + 10,
          painter.height + 6);
      canvas.drawRRect(
          RRect.fromRectAndRadius(tag, const Radius.circular(5)), labelPaint);
      painter.paint(canvas, Offset(tag.left + 5, tag.top + 3));
    }
  }

  @override
  bool shouldRepaint(covariant _DetectionPainter oldDelegate) =>
      oldDelegate.analysis != analysis;
}
