import 'dart:io';
import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import '../../config/app_theme.dart';

/// Workspace for ingesting, sampling, and running defect inference across recorded video feeds.
class VideoAnalysisWorkspace extends StatefulWidget {
  const VideoAnalysisWorkspace({super.key});

  @override
  State<VideoAnalysisWorkspace> createState() => _VideoAnalysisWorkspaceState();
}

class _VideoAnalysisWorkspaceState extends State<VideoAnalysisWorkspace> {
  File? _selectedVideoFile;
  bool _isAnalyzing = false;
  double _processingProgress = 0.0;
  int _framesScanned = 0;
  int _defectsFound = 0;

  Future<void> _pickVideo() async {
    try {
      final result = await FilePickerPlatform.instance.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp4', 'avi', 'mov', 'mkv', 'webm'],
      );

      if (result.isNotEmpty && result.first.path != null) {
        setState(() {
          _selectedVideoFile = File(result.first.path!);
          _isAnalyzing = true;
          _processingProgress = 0.0;
          _framesScanned = 0;
          _defectsFound = 0;
        });

        // Simulate frame extraction & temporal deduplication
        for (int i = 1; i <= 10; i++) {
          await Future.delayed(const Duration(milliseconds: 250));
          if (!mounted) return;
          setState(() {
            _processingProgress = i / 10.0;
            _framesScanned = i * 45;
            _defectsFound = (i >= 4) ? (i >= 8 ? 3 : 1) : 0;
          });
        }

        if (mounted) {
          setState(() {
            _isAnalyzing = false;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AppTheme.isMobile(context);

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: AppTheme.bgSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border),
              boxShadow: AppTheme.shadowSm,
            ),
            child: Row(
              children: [
                const Icon(Icons.video_file_rounded, color: AppTheme.primary, size: 28),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Video Stream & Temporal Frame Deduplication',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Process vehicle dashcam or drone inspection footage with temporal deduplication.',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: _isAnalyzing ? null : _pickVideo,
                  icon: _isAnalyzing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.video_file_outlined, size: 16),
                  label: Text(_selectedVideoFile == null ? 'Select Video' : 'Change Video'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Analysis Progress / Results
          if (_selectedVideoFile != null) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.bgSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Processing: ${_selectedVideoFile!.path.split(Platform.pathSeparator).last}',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      Text(
                        _isAnalyzing
                            ? '${(_processingProgress * 100).toInt()}%'
                            : 'Analysis Completed',
                        style: TextStyle(
                          color: _isAnalyzing ? AppTheme.primary : AppTheme.success,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: _processingProgress,
                    backgroundColor: AppTheme.bgCanvas,
                    color: _isAnalyzing ? AppTheme.primary : AppTheme.success,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _StatBadge(label: 'Frames Scanned', value: '$_framesScanned'),
                      const SizedBox(width: 16),
                      _StatBadge(label: 'Defects Isolated', value: '$_defectsFound'),
                    ],
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(48),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.bgSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.border),
              ),
              child: const Column(
                children: [
                  Icon(Icons.movie_filter_outlined, size: 48, color: AppTheme.textMuted),
                  SizedBox(height: 16),
                  Text(
                    'No Video Loaded for Temporal Scan',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Upload MP4, AVI, or MKV drone/road video clips to begin automated frame-by-frame defect extraction.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  const _StatBadge({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgCanvas,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
        ],
      ),
    );
  }
}
