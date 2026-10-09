import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../config/app_theme.dart';
import '../../../camera/unified_camera_service.dart';
import '../../../core/gps_service.dart';
import '../../../citizen/engines/department_router.dart';
import '../../../citizen/engines/duplicate_detection_engine.dart';
import '../../../citizen/engines/priority_engine.dart';
import '../../../citizen/engines/sla_engine.dart';
import '../../../citizen/models/complaint.dart';
import '../../../citizen/repository/complaint_repository.dart';
import '../../../vision/classifier/defect_classifier_engine.dart';
import '../../../vision/image_quality_engine.dart';
import 'complaint_detail_view.dart';

/// TAB 1 — Quick Report: Production-ready mobile infrastructure observation portal.
///
/// Features:
/// - Universal Android Camera2 & iOS camera engine with rear/front switch, flash, tap-to-focus, zoom
/// - Real-time Android GNSS / GPS acquisition with accuracy tracking in meters
/// - Real-time image quality inspection (blur, exposure, low-light checks)
/// - On-device AI defect classification (potholes, structural concrete cracks, road hazards, etc.)
/// - Severity & Priority calculation engines
/// - Client-side proximity duplicate check
/// - Local offline persistence & automatic background sync
class QuickReportTab extends StatefulWidget {
  const QuickReportTab({super.key});

  @override
  State<QuickReportTab> createState() => _QuickReportTabState();
}

class _QuickReportTabState extends State<QuickReportTab> with WidgetsBindingObserver {
  final UniversalCameraService _cameraService = UniversalCameraService.instance;
  final GpsService _gpsService = GpsService.instance;

  // Capture state
  final List<String> _images = [];
  final List<String> _videos = [];
  final TextEditingController _description = TextEditingController();
  bool _isAnalyzing = false;
  DefectClassificationResult? _aiResult;
  ImageQualityResult? _qualityResult;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _gpsService.acquireBestFix();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _cameraService.stopCamera();
      _gpsService.stopLiveTracking();
    } else if (state == AppLifecycleState.resumed) {
      _gpsService.startLiveTracking();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraService.stopCamera();
    _gpsService.stopLiveTracking();
    _description.dispose();
    super.dispose();
  }

  Future<void> _toggleCamera() async {
    if (_cameraService.isRunning) {
      await _cameraService.stopCamera();
    } else {
      final success = await _cameraService.startCamera();
      if (!success && mounted && _cameraService.lastError != null) {
        _snack(_cameraService.lastError!);
      }
    }
  }

  Future<void> _capturePhoto() async {
    final file = await _cameraService.capturePhoto();
    if (file == null) {
      if (_cameraService.lastError != null) {
        _snack(_cameraService.lastError!);
      }
      return;
    }

    setState(() {
      _images.add(file.path);
    });

    // Run quality check & AI analysis asynchronously
    await _analyzeCapturedMedia(file);
  }

  Future<void> _pickImages() async {
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: true,
      );
      final paths = picked.map((f) => f.path).whereType<String>().toList();
      if (paths.isEmpty) return;

      setState(() {
        _images.addAll(paths);
      });

      await _analyzeCapturedMedia(File(paths.first));
    } catch (e) {
      _snack('Image picker error: $e');
    }
  }

  Future<void> _pickVideos() async {
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.video,
      );
      final paths = picked.map((f) => f.path).whereType<String>().toList();
      if (paths.isEmpty) return;

      setState(() {
        _videos.addAll(paths);
      });
      _snack('Video attached (${paths.length} file)');
    } catch (e) {
      _snack('Video picker error: $e');
    }
  }

  Future<void> _analyzeCapturedMedia(File file) async {
    setState(() {
      _isAnalyzing = true;
      _aiResult = null;
      _qualityResult = null;
    });

    // 1. Image Quality Check
    final quality = await ImageQualityEngine.instance.evaluate(file);

    // 2. AI Defect Classifier Inference
    DefectClassificationResult? classification;
    try {
      classification = await DefectClassifierEngine.instance.classifyImage(file);
    } catch (e) {
      debugPrint('AI defect classification error: $e');
    }

    if (mounted) {
      setState(() {
        _isAnalyzing = false;
        _qualityResult = quality;
        _aiResult = classification;
      });

      if (!quality.isPass) {
        _snack('Quality Notice: ${quality.message}');
      }
    }
  }

  Future<void> _submit() async {
    if (_images.isEmpty && _videos.isEmpty) {
      _snack('Please capture or upload at least one photo or video evidence.');
      return;
    }
    if (_isAnalyzing) {
      _snack('Please wait for on-device AI analysis to complete.');
      return;
    }

    setState(() => _isAnalyzing = true);

    // Ensure we have the latest GPS fix
    Position? pos = _gpsService.currentPosition;
    pos ??= await _gpsService.acquireBestFix();

    final lat = pos?.latitude ?? 0.0;
    final lon = pos?.longitude ?? 0.0;
    final gpsAddress = pos != null ? _gpsService.formattedCoordinates : 'GPS Pending';

    final ai = _aiResult;
    final category = ai?.primaryClass.name ?? 'Road & Pavement Hazards';
    final severity = _mapSeverity(ai);
    final diagnosis = _buildDiagnosis(ai);
    final desc = _description.text.trim().isEmpty
        ? 'Field observation report. Accuracy: ${_gpsService.accuracyLabel}.'
        : _description.text.trim();

    final outcome = await ComplaintRepository.instance.fileCitizenReportAsync(
      category: category,
      severity: severity,
      aiConfidence: ai?.confidence,
      aiDiagnosis: diagnosis,
      description: desc,
      latitude: lat,
      longitude: lon,
      address: gpsAddress,
      images: _images,
      videos: _videos,
    );

    if (!mounted) return;
    setState(() => _isAnalyzing = false);

    if (outcome.isDuplicateFound && outcome.duplicate != null) {
      _showDuplicateDialog(outcome.duplicate!);
      return;
    }
    if (outcome.didJoin && outcome.joinedExisting != null) {
      _snack(
        'Joined existing case (${outcome.joinedExisting!.caseId})! '
        'Confirmations: ${outcome.joinedExisting!.confirmationCount}.',
      );
      _clearAfterSubmit();
      return;
    }
    if (outcome.created != null) {
      final c = outcome.created!;
      _snack('Submitted! Case ${c.caseId} auto-routed to ${c.assignedDepartment}.');
      _clearAfterSubmit();
      _openDetail(c);
    }
  }

  void _clearAfterSubmit() {
    setState(() {
      _images.clear();
      _videos.clear();
      _aiResult = null;
      _qualityResult = null;
      _description.clear();
    });
  }

  void _openDetail(Complaint c) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ComplaintDetailView(complaint: c),
    ));
  }

  void _showDuplicateDialog(DuplicateMatch match) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.warning, size: 22),
            SizedBox(width: 8),
            Text('Similar Issue Nearby', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(match.existing.category, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              '${match.reason} • ${match.distanceMeters.round()}m away',
              style: const TextStyle(color: AppTheme.cyan, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              '${match.existing.confirmationCount} citizen(s) confirmed this • Priority: ${match.existing.priority.label}',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            const Text(
              'Confirming the existing report consolidates municipal work orders and accelerates repair priority.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Create New Separate Report', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.success),
            onPressed: () {
              ComplaintRepository.instance.confirmIssue(
                match.existing.id,
                images: _images,
                videos: _videos,
              );
              Navigator.pop(ctx);
              _snack('Confirmed same issue! Priority escalated.');
              _clearAfterSubmit();
            },
            child: const Text('Confirm Same Issue'),
          ),
        ],
      ),
    );
  }

  SeverityLevel _mapSeverity(DefectClassificationResult? ai) {
    if (ai == null) return SeverityLevel.moderate;
    if (ai.primaryClass.id == 'normal_clean') return SeverityLevel.low;
    final s = ai.severityScore;
    if (s >= 0.75) return SeverityLevel.critical;
    if (s > 0.45) return SeverityLevel.high;
    return SeverityLevel.moderate;
  }

  String _buildDiagnosis(DefectClassificationResult? ai) {
    if (ai == null) {
      return 'Field capture. Location: ${_gpsService.formattedCoordinates}.';
    }
    return 'AI detected ${ai.primaryClass.name} at '
        '${(ai.confidence * 100).toStringAsFixed(1)}% confidence. '
        '${ai.diagnosis} Recommended: ${ai.recommendedAction}';
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = ComplaintRepository.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([_cameraService, _gpsService, repo]),
      builder: (context, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(),
                  const SizedBox(height: 12),
                  _syncBanner(repo),
                  const SizedBox(height: 12),
                  _viewfinderAndControls(),
                  const SizedBox(height: 12),
                  if (_images.isNotEmpty || _videos.isNotEmpty) _mediaThumbnailStrip(),
                  const SizedBox(height: 12),
                  if (_qualityResult != null) _qualityBadge(),
                  const SizedBox(height: 12),
                  _aiResultCard(),
                  const SizedBox(height: 12),
                  _gpsBanner(),
                  const SizedBox(height: 12),
                  _descriptionField(),
                  const SizedBox(height: 16),
                  _submitButton(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _header() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Report a Civil Infrastructure Defect',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
        ),
        SizedBox(height: 4),
        Text(
          'Capture photo/video → GPS detected automatically → AI classifies defect → '
          'Severity & priority computed → Duplicate check → Dispatched to authority.',
          style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.4),
        ),
      ],
    );
  }

  Widget _syncBanner(ComplaintRepository repo) {
    final online = repo.isOnline;
    final pending = repo.pendingSyncCount;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: (online ? AppTheme.success : AppTheme.warning).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: (online ? AppTheme.success : AppTheme.warning).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            online ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
            color: online ? AppTheme.success : AppTheme.warning,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              online
                  ? (pending > 0 ? 'Online — syncing $pending queued observation(s)...' : 'Online — live connection active.')
                  : 'Offline — observations are saved locally and will auto-sync when reconnected.',
              style: const TextStyle(fontSize: 11, color: AppTheme.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _viewfinderAndControls() {
    final isRunning = _cameraService.isRunning;

    return Column(
      children: [
        Container(
          height: 250,
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF030712),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isRunning ? AppTheme.cyan.withValues(alpha: 0.6) : AppTheme.border,
              width: isRunning ? 2.0 : 1.5,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Live camera preview or placeholder
                if (isRunning)
                  GestureDetector(
                    onTapDown: (details) {
                      final box = context.findRenderObject() as RenderBox?;
                      if (box != null) {
                        final local = details.localPosition;
                        final normX = (local.dx / 250.0).clamp(0.0, 1.0);
                        final normY = (local.dy / 250.0).clamp(0.0, 1.0);
                        _cameraService.setFocusPoint(Offset(normX, normY));
                      }
                    },
                    child: _cameraService.buildPreview(),
                  )
                else if (_images.isNotEmpty && File(_images.first).existsSync())
                  Image.file(File(_images.first), fit: BoxFit.cover)
                else
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt_outlined, size: 40, color: Colors.white.withValues(alpha: 0.3)),
                        const SizedBox(height: 8),
                        const Text(
                          'Camera preview off — tap Start Camera or Upload',
                          style: TextStyle(fontSize: 11, color: Colors.white38),
                        ),
                      ],
                    ),
                  ),

                // AI analyzing spinner overlay
                if (_isAnalyzing)
                  Container(
                    color: Colors.black54,
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(color: AppTheme.cyan, strokeWidth: 2.5),
                          ),
                          SizedBox(height: 10),
                          Text(
                            'On-device AI analyzing defect...',
                            style: TextStyle(fontSize: 12, color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Tap-to-focus indicator
                if (_cameraService.lastTapFocusPoint != null)
                  Positioned(
                    left: _cameraService.lastTapFocusPoint!.dx * 200,
                    top: _cameraService.lastTapFocusPoint!.dy * 200,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.cyan, width: 2),
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                  ),

                // Top Viewfinder Controls (Flip camera, Flash, Zoom)
                if (isRunning)
                  Positioned(
                    top: 8,
                    left: 8,
                    right: 8,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Lens indicator chip
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _cameraService.isFrontCamera ? Icons.person_rounded : Icons.landscape_rounded,
                                color: AppTheme.cyan,
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _cameraService.isFrontCamera ? 'FRONT' : 'REAR (DEFECT)',
                                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                        // Action buttons
                        Row(
                          children: [
                            // Flash toggle
                            IconButton(
                              style: IconButton.styleFrom(backgroundColor: Colors.black54),
                              icon: Icon(
                                _cameraService.isFlashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                                color: _cameraService.isFlashOn ? AppTheme.warning : Colors.white,
                                size: 18,
                              ),
                              onPressed: _cameraService.cycleFlash,
                              tooltip: 'Flash Mode',
                            ),
                            const SizedBox(width: 6),
                            // Camera Switch (Rear <-> Front)
                            if (_cameraService.hasMultipleCameras)
                              IconButton(
                                style: IconButton.styleFrom(backgroundColor: Colors.black54),
                                icon: const Icon(Icons.flip_camera_android_rounded, color: Colors.white, size: 18),
                                onPressed: _cameraService.switchCamera,
                                tooltip: 'Switch Camera',
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                // Bottom photo/video count chip
                Positioned(
                  left: 10,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '${_images.length} photo${_images.length == 1 ? '' : 's'} • ${_videos.length} video${_videos.length == 1 ? '' : 's'}',
                      style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),

                // Bottom Right Capture Button when running
                if (isRunning)
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.cyan,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                      onPressed: _capturePhoto,
                      icon: const Icon(Icons.camera_rounded, size: 18, color: Colors.black),
                      label: const Text(
                        'CAPTURE',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.black),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Outdoor-friendly quick buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: isRunning ? AppTheme.warning : AppTheme.cyan,
                  side: BorderSide(color: isRunning ? AppTheme.warning : AppTheme.cyan),
                ),
                onPressed: _cameraService.isStarting ? null : _toggleCamera,
                icon: Icon(isRunning ? Icons.videocam_off_rounded : Icons.videocam_rounded),
                label: Text(isRunning ? 'Stop Camera' : 'Start Camera'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: AppTheme.purple),
                onPressed: _pickImages,
                icon: const Icon(Icons.add_photo_alternate_rounded),
                label: const Text('Upload Photos'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: AppTheme.warning),
                onPressed: _pickVideos,
                icon: const Icon(Icons.videocam_rounded),
                label: const Text('Add Video'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _mediaThumbnailStrip() {
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _images.length + _videos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final isImg = index < _images.length;
          final path = isImg ? _images[index] : _videos[index - _images.length];
          return Stack(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.cyan.withValues(alpha: 0.5)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: isImg && File(path).existsSync()
                      ? Image.file(File(path), fit: BoxFit.cover)
                      : Container(
                          color: Colors.black45,
                          child: Icon(
                            isImg ? Icons.image_rounded : Icons.videocam_rounded,
                            color: AppTheme.cyan,
                          ),
                        ),
                ),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isImg) {
                        _images.removeAt(index);
                      } else {
                        _videos.removeAt(index - _images.length);
                      }
                    });
                  },
                  child: Container(
                    decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle),
                    padding: const EdgeInsets.all(2),
                    child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _qualityBadge() {
    final q = _qualityResult;
    if (q == null) return const SizedBox.shrink();
    final isPass = q.isPass;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: (isPass ? AppTheme.success : AppTheme.warning).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: (isPass ? AppTheme.success : AppTheme.warning).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            isPass ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
            color: isPass ? AppTheme.success : AppTheme.warning,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Image Quality: ${q.message} (Sharpness Score: ${q.blurScore.toStringAsFixed(0)})',
              style: const TextStyle(fontSize: 11, color: AppTheme.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _aiResultCard() {
    final ai = _aiResult;
    if (ai == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.bgSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border),
        ),
        child: const Row(
          children: [
            Icon(Icons.psychology_rounded, color: AppTheme.purple, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'AI analysis runs automatically when photo is captured. Defect category, severity, priority and department are computed locally.',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
      );
    }

    final severity = _mapSeverity(ai);
    final category = ai.primaryClass.name;
    final priority = PriorityEngine.instance.levelFor(
      PriorityEngine.instance.computeScore(severity: severity, confirmationCount: 1),
    );
    final department = DepartmentRouter.instance.departmentFor(ai.primaryClass.id);
    final eta = SLAEngine.instance.estimatedTimeFor(severity);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cyan.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, color: AppTheme.purple, size: 16),
                  SizedBox(width: 6),
                  Text('On-Device AI Classification', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.purple.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${(ai.confidence * 100).toStringAsFixed(1)}% CONFIDENCE',
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppTheme.purple),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(category, style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(ai.diagnosis, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.4)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _tag('Severity: ${severity.label}', _severityColor(severity)),
              _tag('Priority: ${priority.label}', AppTheme.warning),
              _tag('Dept: $department', AppTheme.cyan),
              _tag('ETA: $eta', AppTheme.success),
            ],
          ),
        ],
      ),
    );
  }

  Widget _gpsBanner() {
    final isAcquiring = _gpsService.isAcquiring;
    final formatted = _gpsService.formattedCoordinates;
    final accuracyStr = _gpsService.accuracyLabel;
    final grade = _gpsService.accuracyGrade;

    final Color gradeColor = switch (grade) {
      GpsAccuracyGrade.excellent || GpsAccuracyGrade.good => AppTheme.success,
      GpsAccuracyGrade.moderate => AppTheme.warning,
      _ => AppTheme.error,
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: gradeColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: gradeColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.location_on_rounded, color: gradeColor, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('Capture Location (Real GNSS/GPS)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
                    const SizedBox(width: 6),
                    if (isAcquiring)
                      const SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.cyan),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(formatted, style: const TextStyle(fontSize: 11, color: AppTheme.textPrimary)),
                Text(accuracyStr, style: TextStyle(fontSize: 10, color: gradeColor, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _gpsService.acquireBestFix(),
            icon: const Icon(Icons.my_location_rounded, color: AppTheme.cyan, size: 20),
            tooltip: 'Refresh GPS Fix',
          ),
        ],
      ),
    );
  }

  Widget _descriptionField() {
    return TextField(
      controller: _description,
      maxLines: 2,
      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
      decoration: const InputDecoration(
        labelText: 'Observations / Defect Description (optional)',
        hintText: 'e.g. Deep pothole causing vehicular deflection on left carriageway...',
      ),
    );
  }

  Widget _submitButton() {
    final ready = (_images.isNotEmpty || _videos.isNotEmpty) && !_isAnalyzing;
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: ready ? AppTheme.cyan : AppTheme.textMuted,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: ready ? _submit : null,
        icon: const Icon(Icons.send_rounded, color: Colors.black),
        label: const Text(
          'ANALYZE, ROUTE & SUBMIT REPORT',
          style: TextStyle(fontWeight: FontWeight.w800, color: Colors.black, letterSpacing: 0.3),
        ),
      ),
    );
  }

  Widget _tag(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
      );

  Color _severityColor(SeverityLevel s) => switch (s) {
        SeverityLevel.critical || SeverityLevel.high => AppTheme.error,
        SeverityLevel.moderate => AppTheme.warning,
        SeverityLevel.low => AppTheme.success,
      };
}
