import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../vision/classifier/defect_classifier_engine.dart';

/// Clean, Enterprise Image Inspection & Multi-Class Classification Studio.
class ImageAnalysisWorkspace extends StatefulWidget {
  const ImageAnalysisWorkspace({super.key});

  @override
  State<ImageAnalysisWorkspace> createState() => _ImageAnalysisWorkspaceState();
}

class _ImageAnalysisWorkspaceState extends State<ImageAnalysisWorkspace> {
  final DefectClassifierEngine _classifier = DefectClassifierEngine.instance;

  File? _selectedFile;
  DefectClassificationResult? _result;
  bool _isAnalyzing = false;
  bool _showHeatmap = true;
  bool _showBoxes = true;

  @override
  Widget build(BuildContext context) {
    final isMobile = AppTheme.isMobile(context);

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header Bar
          _buildHeader(context),
          const SizedBox(height: 20),

          // 2. Main Studio (Image Preview & Analysis Results)
          if (_selectedFile == null)
            _buildEmptyUploadPrompt(context)
          else if (!isMobile)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: Image Viewport with Heatmap & Detection Boxes
                Expanded(
                  flex: 6,
                  child: _buildImageViewport(context),
                ),
                const SizedBox(width: 20),
                // Right: Multi-Class Probability Distribution & AI Diagnosis
                Expanded(
                  flex: 5,
                  child: _buildResultsPanel(context),
                ),
              ],
            )
          else ...[
            _buildImageViewport(context),
            const SizedBox(height: 20),
            _buildResultsPanel(context),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.accentBlueLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.image_search_rounded, color: AppTheme.accentBlue, size: 24),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Image Inspection & Multi-Class Defect Reasoning',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Upload infrastructure imagery for real-time defect classification, Grad-CAM attention analysis, and severity scoring.',
                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: _isAnalyzing ? null : _pickImage,
            icon: _isAnalyzing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.file_upload_outlined, size: 16),
            label: Text(_selectedFile == null ? 'Select Image' : 'New Image'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyUploadPrompt(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border, width: 1.5),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: AppTheme.primaryLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.cloud_upload_outlined, size: 48, color: AppTheme.primary),
          ),
          const SizedBox(height: 18),
          const Text(
            'Upload Asset Image for AI Inspection',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 8),
          const Text(
            'Supports PNG, JPG, JPEG, and WebP (Solar panels, road surfaces, concrete pillars, metal assets).',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.folder_open_rounded, size: 18),
            label: const Text('Browse Files from Disk'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
          ),
        ],
      ),
    );
  }

  Widget _buildImageViewport(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Source Asset Viewport (${_result?.imageWidth ?? 0} × ${_result?.imageHeight ?? 0} px)',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
              ),
              Wrap(
                spacing: 8,
                children: [
                  _buildToggleChip(
                    label: 'Heatmap',
                    icon: Icons.blur_on_rounded,
                    isActive: _showHeatmap,
                    onTap: () => setState(() => _showHeatmap = !_showHeatmap),
                  ),
                  _buildToggleChip(
                    label: 'Bounding Box',
                    icon: Icons.crop_free_rounded,
                    isActive: _showBoxes,
                    onTap: () => setState(() => _showBoxes = !_showBoxes),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 440,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(_selectedFile!, fit: BoxFit.contain),

                  // Grad-CAM Attention Heatmap
                  if (_showHeatmap && _result != null)
                    CustomPaint(
                      painter: _GradCamPainter(
                        heatmap: _result!.heatmapGrid,
                        gridW: _result!.heatmapWidth,
                        gridH: _result!.heatmapHeight,
                      ),
                    ),

                  // Defect Bounding Boxes
                  if (_showBoxes && _result != null)
                    CustomPaint(
                      painter: _DefectBoxPainter(boxes: _result!.detectedBoxes),
                    ),

                  if (_isAnalyzing)
                    Container(
                      color: Colors.black45,
                      child: const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleChip({
    required String label,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.primaryLight : AppTheme.bgSurfaceSubtle,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isActive ? AppTheme.primary : AppTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isActive ? AppTheme.primary : AppTheme.textSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isActive ? AppTheme.primary : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsPanel(BuildContext context) {
    if (_result == null) return const SizedBox();

    final res = _result!;
    final isNormal = res.primaryClass.id == 'normal_clean';

    return Container(
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
          // 1. Primary Classification Banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isNormal ? AppTheme.successLight : AppTheme.errorLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isNormal ? AppTheme.success.withValues(alpha: 0.3) : AppTheme.error.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isNormal ? Icons.verified_rounded : Icons.report_problem_rounded,
                  color: isNormal ? AppTheme.success : AppTheme.error,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        res.primaryClass.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isNormal ? AppTheme.successDark : AppTheme.errorDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Confidence: ${(res.confidence * 100).toStringAsFixed(1)}% • Latency: ${res.latencyMs.toStringAsFixed(1)}ms',
                        style: TextStyle(
                          fontSize: 12,
                          color: isNormal ? AppTheme.successDark.withValues(alpha: 0.8) : AppTheme.errorDark.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // 2. Defect Severity Rating
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Severity Level Assessment', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
              Text(res.severityLevel, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: res.primaryClass.color)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: res.severityScore,
              minHeight: 8,
              backgroundColor: AppTheme.bgSurfaceSubtle,
              valueColor: AlwaysStoppedAnimation<Color>(res.primaryClass.color),
            ),
          ),
          const SizedBox(height: 20),

          // 3. Multi-Class Probability Distribution
          const Text('Class Probability Breakdown (Softmax)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
          const SizedBox(height: 10),
          ...res.predictions.map((p) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: p.defectClass.color)),
                          const SizedBox(width: 8),
                          Text(p.defectClass.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
                        ],
                      ),
                      Text('${(p.confidence * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: p.confidence,
                      minHeight: 5,
                      backgroundColor: AppTheme.bgSurfaceSubtle,
                      valueColor: AlwaysStoppedAnimation<Color>(p.defectClass.color),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 16),

          // 4. AI Diagnosis Summary & Recommended Action
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.bgSurfaceSubtle,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Diagnostic Insight', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                const SizedBox(height: 4),
                Text(res.diagnosis, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.4)),
                const SizedBox(height: 8),
                const Text('Recommended Protocol:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                const SizedBox(height: 4),
                Text(res.recommendedAction, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.4)),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Action Button
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Generated Defect Ticket #${DateTime.now().millisecondsSinceEpoch.toString().substring(7)} for ${res.primaryClass.name}'),
                    backgroundColor: AppTheme.success,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              icon: const Icon(Icons.assignment_turned_in_rounded, size: 18),
              label: const Text('Generate Work Order Ticket'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    try {
      final result = await FilePickerPlatform.instance.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      );

      if (result.isNotEmpty && result.first.path != null) {
        final file = File(result.first.path!);
        setState(() {
          _selectedFile = file;
          _isAnalyzing = true;
          _result = null;
        });

        final analysis = await _classifier.classifyImage(file);

        if (mounted) {
          setState(() {
            _result = analysis;
            _isAnalyzing = false;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }
}

/// Custom painter for rendering Grad-CAM attention heatmap overlay
class _GradCamPainter extends CustomPainter {
  _GradCamPainter({
    required this.heatmap,
    required this.gridW,
    required this.gridH,
  });

  final List<double> heatmap;
  final int gridW;
  final int gridH;

  @override
  void paint(Canvas canvas, Size size) {
    if (heatmap.isEmpty) return;

    final cellW = size.width / gridW;
    final cellH = size.height / gridH;

    for (int gy = 0; gy < gridH; gy++) {
      for (int gx = 0; gx < gridW; gx++) {
        final idx = gy * gridW + gx;
        final heat = heatmap[idx];
        if (heat < 0.15) continue; // Skip cool areas

        // Map heat (0..1) to Soft Red/Orange/Yellow transparent circles
        final color = heat > 0.6
            ? Colors.red.withValues(alpha: heat * 0.45)
            : (heat > 0.35
                ? Colors.amber.withValues(alpha: heat * 0.35)
                : Colors.cyan.withValues(alpha: heat * 0.25));

        final paint = Paint()
          ..color = color
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);

        final rect = Rect.fromLTWH(gx * cellW, gy * cellH, cellW, cellH);
        canvas.drawRect(rect, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GradCamPainter oldDelegate) => true;
}

/// Custom painter for localized defect bounding boxes
class _DefectBoxPainter extends CustomPainter {
  _DefectBoxPainter({required this.boxes});

  final List<DefectBox> boxes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in boxes) {
      final rect = Rect.fromLTRB(
        b.rect.left * size.width,
        b.rect.top * size.height,
        b.rect.right * size.width,
        b.rect.bottom * size.height,
      );

      final boxPaint = Paint()
        ..color = b.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;

      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)), boxPaint);

      // Label background & text
      final bgPaint = Paint()..color = b.color;
      final textSpan = TextSpan(
        text: ' ${b.label} (${(b.confidence * 100).toStringAsFixed(0)}%) ',
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      final labelRect = Rect.fromLTWH(rect.left, rect.top - 20, textPainter.width, 20);
      canvas.drawRRect(RRect.fromRectAndRadius(labelRect, const Radius.circular(4)), bgPaint);
      textPainter.paint(canvas, Offset(rect.left, rect.top - 18));
    }
  }

  @override
  bool shouldRepaint(covariant _DefectBoxPainter oldDelegate) => true;
}
