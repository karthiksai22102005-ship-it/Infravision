import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:infravision_camera/infravision_camera.dart';

import '../../../config/app_theme.dart';
import '../../../core/gps_helper.dart';
import '../../../citizen/engines/department_router.dart';
import '../../../citizen/engines/duplicate_detection_engine.dart';
import '../../../citizen/engines/priority_engine.dart';
import '../../../citizen/engines/sla_engine.dart';
import '../../../citizen/models/complaint.dart';
import '../../../citizen/repository/complaint_repository.dart';
import '../../../vision/classifier/defect_classifier_engine.dart';
import 'complaint_detail_view.dart';

/// TAB 1 — Quick Report: an intelligent, autonomous complaint creation flow.
///
/// Capture/upload photo or video -> auto GPS -> on-device AI analysis ->
/// category -> severity -> priority -> duplicate check -> join or create new ->
/// auto department routing -> Case ID -> starts real-time tracking.
class QuickReportTab extends StatefulWidget {
  const QuickReportTab({super.key});

  @override
  State<QuickReportTab> createState() => _QuickReportTabState();
}

class _QuickReportTabState extends State<QuickReportTab> {
  // Camera
  CameraStartResult? _cameraStart;
  StreamSubscription<CameraFrame>? _frameSub;
  CameraFrame? _latestFrame;
  bool _cameraRunning = false;
  bool _cameraStarting = false;
  String _cameraStatus = 'Camera not started';

  // Capture state
  final List<String> _images = [];
  final List<String> _videos = [];
  final TextEditingController _description = TextEditingController();
  bool _isAnalyzing = false;
  DefectClassificationResult? _aiResult;

  String _gpsString = GpsHelper.defaultCoordinates;
  double _lat = 17.3850;
  double _lon = 78.4867;
  bool _gpsLoading = false;

  @override
  void initState() {
    super.initState();
    _refreshGps();
  }

  @override
  void dispose() {
    _frameSub?.cancel();
    if (_cameraRunning) InfravisionCamera.stopCamera();
    _description.dispose();
    super.dispose();
  }
  Future<void> _refreshGps() async {
    setState(() => _gpsLoading = true);
    final ll = await GpsHelper.getLatLng();
    final str = await GpsHelper.getCoordinatesString();
    if (mounted) {
      setState(() {
        _gpsString = str;
        if (ll != null) {
          _lat = ll.lat;
          _lon = ll.lon;
        }
        _gpsLoading = false;
      });
    }
  }

  Future<void> _toggleCamera() async {
    if (_cameraRunning) {
      await InfravisionCamera.stopCamera();
      if (mounted) {
        setState(() {
          _cameraRunning = false;
          _cameraStatus = 'Camera stopped.';
        });
      }
      return;
    }
    setState(() {
      _cameraStarting = true;
      _cameraStatus = 'Looking for camera...';
    });
    try {
      final devices = await InfravisionCamera.availableCameras();
      if (devices.isEmpty) {
        if (mounted) {
          setState(() {
            _cameraStarting = false;
            _cameraStatus = 'No camera found — use Upload Photo instead.';
          });
        }
        return;
      }
      final start = await InfravisionCamera.startCamera(devices.first.id);
      _frameSub ??= InfravisionCamera.frames.listen((f) => _latestFrame = f);
      if (mounted) {
        setState(() {
          _cameraStart = start;
          _cameraRunning = true;
          _cameraStarting = false;
          _cameraStatus = 'Camera running: ${devices.first.name}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cameraStarting = false;
          _cameraStatus = 'Camera error: $e — use Upload Photo instead.';
        });
      }
    }
  }

  Future<void> _capturePhoto() async {
    final frame = _latestFrame;
    if (frame == null) {
      if (mounted) {
        setState(() => _cameraStatus = 'No frame available yet — retry.');
      }
      return;
    }
    try {
      final bmp = _bgraToBmp(frame.bytes, frame.width, frame.height);
      final decoded = img.decodeImage(bmp);
      if (decoded == null) throw Exception('Failed to decode camera frame');
      final png = img.encodePng(decoded);
      final dir = Directory('${Directory.systemTemp.path}/infravision_capture');
      await dir.create(recursive: true);
      final file = File('${dir.path}/capture_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(png);
      _analyzeCaptured(file);
    } catch (e) {
      if (mounted) setState(() => _cameraStatus = 'Capture failed: $e');
    }
  }

  Future<void> _pickImages() async {
    final picked = await FilePicker.pickFiles(type: FileType.image);
    final paths = picked.map((f) => f.path).whereType<String>().toList();
    if (paths.isEmpty) return;
    setState(() => _images.addAll(paths));
    await _analyzeCaptured(File(paths.first));
  }

  Future<void> _pickVideos() async {
    final picked = await FilePicker.pickFiles(type: FileType.video);
    final paths = picked.map((f) => f.path).whereType<String>().toList();
    if (paths.isEmpty) return;
    setState(() => _videos.addAll(paths));
  }

  Future<void> _analyzeCaptured(File file) async {
    setState(() {
      _isAnalyzing = true;
      _aiResult = null;
    });
    DefectClassificationResult? result;
    try {
      result = await DefectClassifierEngine.instance.classifyImage(file);
    } catch (e) {
      debugPrint('AI analysis failed: $e');
    }
    if (mounted) {
      setState(() {
        _isAnalyzing = false;
        _aiResult = result;
      });
    }
  }

  Uint8List _bgraToBmp(Uint8List bgra, int w, int h) {
    final rowSize = (w * 3 + 3) & ~3;
    final pixelArraySize = rowSize * h;
    final fileSize = 54 + pixelArraySize;
    final out = ByteData(fileSize);
    void writeU16(int o, int v) {
      out.setUint8(o, v & 0xFF);
      out.setUint8(o + 1, (v >> 8) & 0xFF);
    }
    void writeU32(int o, int v) {
      out.setUint8(o, v & 0xFF);
      out.setUint8(o + 1, (v >> 8) & 0xFF);
      out.setUint8(o + 2, (v >> 16) & 0xFF);
      out.setUint8(o + 3, (v >> 24) & 0xFF);
    }
    out.setUint8(0, 0x42);
    out.setUint8(1, 0x4D);
    writeU32(2, fileSize);
    writeU32(6, 0);
    writeU32(10, 54);
    writeU32(14, 40);
    writeU32(18, w);
    writeU32(22, h);
    writeU16(26, 1);
    writeU16(28, 24);
    writeU32(30, 0);
    writeU32(34, pixelArraySize);
    writeU32(38, 2835);
    writeU32(42, 2835);
    writeU32(46, 0);
    writeU32(50, 0);
    for (int y = 0; y < h; y++) {
      final srcRow = (h - 1 - y) * w * 4;
      final dst = 54 + y * rowSize;
      for (int x = 0; x < w; x++) {
        final si = srcRow + x * 4;
        final di = dst + x * 3;
        out.setUint8(di, bgra[si]);
        out.setUint8(di + 1, bgra[si + 1]);
        out.setUint8(di + 2, bgra[si + 2]);
      }
    }
    return out.buffer.asUint8List();
  }
  Future<void> _submit() async {
    if (_images.isEmpty && _videos.isEmpty) {
      _snack('Add a photo or video first.');
      return;
    }
    if (_isAnalyzing) {
      _snack('Please wait for AI analysis to finish.');
      return;
    }
    setState(() => _isAnalyzing = true);

    final ai = _aiResult;
    final category =
        ai?.primaryClass.id ?? 'general'; // used for routing/duplicate checks
    final severity = _mapSeverity(ai);
    final diagnosis = _buildDiagnosis(ai);
    final desc = _description.text.trim().isEmpty
        ? 'Citizen report. Location (GPS): $_gpsString.'
        : _description.text.trim();

    final outcome = await ComplaintRepository.instance.fileCitizenReportAsync(
      category: category,
      severity: severity,
      aiConfidence: ai?.confidence,
      aiDiagnosis: diagnosis,
      description: desc,
      latitude: _lat,
      longitude: _lon,
      address: _gpsString,
      images: _images,
      videos: _videos,
    );

    if (!mounted) return;
    setState(() => _isAnalyzing = false);

    if (outcome.isDuplicateFound && outcome.duplicate != null) {
      // Citizen found an existing issue nearby -> offer confirm or create new.
      _showDuplicateDialog(outcome.duplicate!);
      return;
    }
    if (outcome.didJoin && outcome.joinedExisting != null) {
      _snack(
          'You confirmed an existing issue (${outcome.joinedExisting!.caseId}). '
          'It now has ${outcome.joinedExisting!.confirmationCount} confirmations.');
      _clearAfterSubmit();
      return;
    }
    if (outcome.created != null) {
      final c = outcome.created!;
      _snack('Reported! Case ${c.caseId} auto-routed to ${c.assignedDepartment}. '
          'Tracking started — ${SLAEngineLabel.eta(c)}.');
      _clearAfterSubmit();
      // Show a shortcut to the case detail.
      _openDetail(c);
    }
  }

  void _clearAfterSubmit() {
    setState(() {
      _images.clear();
      _videos.clear();
      _aiResult = null;
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
        title: const Text('Existing issue found nearby', style: TextStyle(color: AppTheme.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(match.existing.category, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('${match.reason} • ${match.distanceMeters.round()}m away',
                style: const TextStyle(color: AppTheme.cyan)),
            const SizedBox(height: 4),
            Text(
                '${match.existing.confirmationCount} citizens already confirmed this • priority ${match.existing.priority.label}',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            const SizedBox(height: 12),
            const Text(
                'Join the existing report to prevent a duplicate instead of filing a new one.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Create new report', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.success),
            onPressed: () {
              ComplaintRepository.instance.confirmIssue(match.existing.id,
                  images: _images, videos: _videos);
              Navigator.pop(ctx);
              _snack('Confirmed same issue! Affected count increased.');
              setState(() {
                _images.clear();
                _videos.clear();
                _aiResult = null;
                _description.clear();
              });
            },
            child: const Text('Confirm same issue'),
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
      return 'On-device AI analysis. Captured location (GPS): $_gpsString.';
    }
    return 'AI detected ${ai.primaryClass.name} at '
        '${(ai.confidence * 100).toStringAsFixed(1)}% confidence. '
        '${ai.diagnosis} Recommended: ${ai.recommendedAction}';
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg), behavior: SnackBarBehavior.floating));
  }
  @override
  Widget build(BuildContext context) {
    final repo = ComplaintRepository.instance;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Report a Civil Infrastructure Defect',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 4),
              const Text(
                'Capture photo/video -> GPS detected automatically -> AI analyzes the issue -> '
                'category, severity & priority detected -> duplicate check -> auto-routed.',
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 14),
              ListenableBuilder(
                listenable: repo,
                builder: (context, _) {
                  return _syncBanner(repo);
                },
              ),
              const SizedBox(height: 14),
              _captureControls(repo),
              const SizedBox(height: 14),
              _preview(),
              const SizedBox(height: 14),
              _aiResultCard(),
              const SizedBox(height: 14),
              _gpsBanner(),
              const SizedBox(height: 14),
              TextField(
                controller: _description,
                maxLines: 3,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Describe the issue (optional)',
                  hintText: 'e.g. Deep pothole near the bus stop...',
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: _ready() ? AppTheme.cyan : AppTheme.textMuted),
                  onPressed: _ready() ? _submit : null,
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Analyze, Route & Submit Report', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _ready() => (_images.isNotEmpty || _videos.isNotEmpty) && !_isAnalyzing;

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
      child: Row(children: [
        Icon(
          online ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
          color: online ? AppTheme.success : AppTheme.warning,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            online
                ? (pending > 0 ? 'Online — syncing $pending queued report(s)...' : 'Online — reports sync automatically.')
                : 'Offline — reports are saved locally and will auto-sync when you are back online.',
            style: const TextStyle(fontSize: 11, color: AppTheme.textPrimary),
          ),
        ),
      ]),
    );
  }

  Widget _captureControls(ComplaintRepository repo) {
    return Column(children: [
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppTheme.cyan),
            onPressed: _cameraStarting ? null : _toggleCamera,
            icon: Icon(_cameraRunning ? Icons.videocam_off_rounded : Icons.videocam_rounded),
            label: Text(_cameraRunning ? 'Stop Camera' : 'Start Camera'),
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
      ]),
      const SizedBox(height: 6),
      Text(_cameraStatus, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
    ]);
  }
  Widget _preview() {
    return Container(
      height: 210,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF020617),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border, width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_images.isNotEmpty && File(_images.first).existsSync())
              Image.file(File(_images.first), fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink())
            else if (_cameraRunning && _cameraStart != null)
              Texture(textureId: _cameraStart!.textureId)
            else
              const Center(
                  child: Text('Camera preview off — start camera or upload a photo',
                      style: TextStyle(fontSize: 11, color: Colors.white38))),
            if (_isAnalyzing)
              Container(
                color: Colors.black54,
                child: const Center(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: AppTheme.cyan, strokeWidth: 2)),
                  SizedBox(height: 10),
                  Text('AI analyzing the defect locally...', style: TextStyle(fontSize: 12, color: AppTheme.textPrimary)),
                ])),
              ),
            Positioned(
              right: 10,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(20)),
                child: Text(
                  '${_images.length} photo${_images.length == 1 ? '' : 's'} • ${_videos.length} video${_videos.length == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            if (_cameraRunning)
              Positioned(
                right: 10,
                top: 10,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.cyan, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
                  onPressed: _capturePhoto,
                  icon: const Icon(Icons.photo_camera_rounded, size: 16),
                  label: const Text('Capture', style: TextStyle(fontSize: 11)),
                ),
              ),
          ],
        ),
      ),
    );
  }
  Widget _aiResultCard() {
    final ai = _aiResult;
    if (ai == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppTheme.bgSurface, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.border)),
        child: const Row(children: [
          Icon(Icons.psychology_rounded, color: AppTheme.purple, size: 18),
          SizedBox(width: 8),
          Expanded(child: Text('AI analysis will run automatically after you add a photo. Category, severity, priority, department and ETA will be computed.',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary))),
        ]),
      );
    }

    final severity = _mapSeverity(ai);
    final category = ai.primaryClass.name;
    final priority = PriorityEngine.instance.levelFor(
        PriorityEngine.instance.computeScore(severity: severity, confirmationCount: 1));
    final department = DepartmentRouter.instance.departmentFor(ai.primaryClass.id);
    final eta = SLAEngine.instance.estimatedTimeFor(severity);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppTheme.bgSurface, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('AI Analysis Result', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
          const SizedBox(height: 8),
          Text('Category: $category', style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
          Text('Confidence: ${(ai.confidence * 100).toStringAsFixed(1)}%',
              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          Text(ai.diagnosis, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.4)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _tag('Severity: ${severity.label}', _severityColor(severity)),
            _tag('Priority: ${priority.label}', AppTheme.warning),
            _tag('Dept: $department', AppTheme.cyan),
            _tag('ETA: $eta', AppTheme.success),
          ]),
        ],
      ),
    );
  }
  Widget _gpsBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppTheme.success.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.success.withValues(alpha: 0.3))),
      child: Row(children: [
        const Icon(Icons.location_on_rounded, color: AppTheme.success, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Capture Location (GPS — auto-detected)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
            const SizedBox(height: 2),
            Text(_gpsLoading ? 'Resolving GPS...' : _gpsString, style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary)),
          ]),
        ),
        IconButton(
          onPressed: _refreshGps,
          icon: const Icon(Icons.my_location_rounded, color: AppTheme.success, size: 18),
          tooltip: 'Recapture / correct location',
        ),
      ]),
    );
  }

  Widget _tag(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withValues(alpha: 0.4))),
        child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
      );

  Color _severityColor(SeverityLevel s) => switch (s) {
        SeverityLevel.critical || SeverityLevel.high => AppTheme.error,
        SeverityLevel.moderate => AppTheme.warning,
        SeverityLevel.low => AppTheme.success,
      };
}
