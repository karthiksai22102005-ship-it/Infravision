import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../core/network/models.dart';
import '../../core/widgets/common.dart';

enum CameraMode { photo, video }

/// Camera screen supporting real-time Zoom In/Out (pinch gesture, buttons, slider)
/// and dual capture modes: Photo and Video.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _ctrl;
  List<CameraDescription> _cams = [];
  int _idx = 0;
  String? _problem;
  bool _permanent = false;
  bool _flash = false;
  bool _taking = false;

  // Zoom control state
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _currentZoom = 1.0;
  double _baseZoom = 1.0;
  bool _showZoomSlider = false;

  // Mode: Photo vs Video
  CameraMode _mode = CameraMode.photo;
  bool _isRecording = false;
  Duration _recordDuration = Duration.zero;
  Timer? _recordTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    final s = context.read<AppState>().s;
    var st = await Permission.camera.status;
    if (!st.isGranted) st = await Permission.camera.request();
    if (!st.isGranted) {
      if (!mounted) return;
      setState(() {
        _problem = s('permCamera');
        _permanent = st.isPermanentlyDenied;
      });
      return;
    }
    try {
      _cams = await availableCameras();
      if (_cams.isEmpty) throw CameraException('none', 'No camera found');
      await _open();
    } on CameraException {
      if (mounted) {
        setState(() => _problem =
            'No usable camera found on this device. You can still pick photos or videos from the gallery.');
      }
    }
  }

  Future<void> _open() async {
    await _ctrl?.dispose();
    final c = CameraController(_cams[_idx], ResolutionPreset.high,
        enableAudio: false);
    _ctrl = c;
    await c.initialize();

    // Query hardware zoom boundaries
    try {
      _minZoom = await c.getMinZoomLevel();
      _maxZoom = await c.getMaxZoomLevel();
      _currentZoom = _minZoom.clamp(1.0, _maxZoom);
      await c.setZoomLevel(_currentZoom);
    } catch (_) {
      _minZoom = 1.0;
      _maxZoom = 1.0;
      _currentZoom = 1.0;
    }

    if (mounted) setState(() => _problem = null);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        (_ctrl == null || !_ctrl!.value.isInitialized)) {
      _init();
    }
    if (state == AppLifecycleState.inactive) {
      if (_isRecording) _stopVideo();
      _ctrl?.dispose();
      _ctrl = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recordTimer?.cancel();
    _ctrl?.dispose();
    super.dispose();
  }

  // --- Zoom In / Zoom Out Handlers ---
  Future<void> _setZoom(double target) async {
    if (_ctrl == null || !_ctrl!.value.isInitialized) return;
    final clamped = target.clamp(_minZoom, _maxZoom);
    try {
      await _ctrl!.setZoomLevel(clamped);
      if (mounted) setState(() => _currentZoom = clamped);
    } catch (_) {}
  }

  void _zoomIn() => _setZoom(_currentZoom + 0.5);
  void _zoomOut() => _setZoom(_currentZoom - 0.5);

  void _onScaleStart(ScaleStartDetails details) {
    _baseZoom = _currentZoom;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final target = _baseZoom * details.scale;
    _setZoom(target);
  }

  // --- Photo Capture ---
  Future<void> _capture() async {
    if (_ctrl == null || !_ctrl!.value.isInitialized || _taking) return;
    setState(() => _taking = true);
    try {
      final f = await _ctrl!.takePicture();
      if (!mounted) return;
      final savedPath = await context.read<AppState>().addPhoto(f.path);
      if (mounted) {
        Navigator.pushNamed(context, '/detection_review', arguments: savedPath);
      }
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } on CameraException {
      if (mounted) {
        showSnack(context, 'Could not capture the photo. Try again.');
      }
    } finally {
      if (mounted) setState(() => _taking = false);
    }
  }

  // --- Video Recording ---
  Future<void> _startVideo() async {
    if (_ctrl == null || !_ctrl!.value.isInitialized || _isRecording) return;
    try {
      await _ctrl!.startVideoRecording();
      setState(() {
        _isRecording = true;
        _recordDuration = Duration.zero;
      });
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() => _recordDuration += const Duration(seconds: 1));
      });
    } on CameraException catch (e) {
      if (mounted) {
        showSnack(context, 'Could not start video recording: ${e.description}');
      }
    }
  }

  Future<void> _stopVideo() async {
    if (_ctrl == null || !_isRecording) return;
    _recordTimer?.cancel();
    try {
      final xfile = await _ctrl!.stopVideoRecording();
      setState(() => _isRecording = false);
      if (!mounted) return;
      await context.read<AppState>().addVideo(xfile.path);
      if (mounted) {
        showSnack(context,
            'Video recorded successfully (${_recordDuration.inSeconds}s)');
      }
    } on CameraException catch (e) {
      if (mounted) {
        showSnack(context, 'Error stopping recording: ${e.description}');
      }
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _isRecording = false);
    }
  }

  // --- Gallery Media Picker (Photos & Videos) ---
  Future<void> _gallery() async {
    if (_mode == CameraMode.video) {
      final file = await ImagePicker().pickVideo(source: ImageSource.gallery);
      if (file != null && mounted) {
        try {
          await context.read<AppState>().addVideo(file.path);
          if (mounted) showSnack(context, 'Video added: ${file.name}');
        } on ApiException catch (e) {
          if (mounted) showSnack(context, e.message);
        }
      }
    } else {
      final files =
          await ImagePicker().pickMultiImage(limit: 5, imageQuality: 85);
      if (!mounted) return;
      final st = context.read<AppState>();
      for (final f in files) {
        try {
          await st.addPhoto(f.path);
        } on ApiException catch (e) {
          if (mounted) showSnack(context, e.message);
          break;
        }
      }
      if (files.isNotEmpty && mounted) {
        Navigator.pushNamed(context, '/detection_review',
            arguments: files.first.path);
      }
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>().s;
    final ready = _ctrl?.value.isInitialized ?? false;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(_mode == CameraMode.photo ? 'Take Photo' : 'Record Video'),
        actions: [
          IconButton(
            icon: Icon(_flash ? Icons.flash_on : Icons.flash_off),
            onPressed: !ready
                ? null
                : () async {
                    _flash = !_flash;
                    await _ctrl!
                        .setFlashMode(_flash ? FlashMode.torch : FlashMode.off);
                    setState(() {});
                  },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _problem != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.no_photography,
                              color: Colors.white54, size: 56),
                          const SizedBox(height: 12),
                          Text(_problem!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white70)),
                          const SizedBox(height: 12),
                          if (_permanent)
                            OutlinedButton(
                                onPressed: openAppSettings,
                                child: Text(s('openSettings')))
                          else
                            OutlinedButton(
                                onPressed: _init, child: Text(s('retry'))),
                        ],
                      ),
                    ),
                  )
                : ready
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          // Pinch-to-zoom gesture detector covering camera preview
                          GestureDetector(
                            onScaleStart: _onScaleStart,
                            onScaleUpdate: _onScaleUpdate,
                            child: CameraPreview(_ctrl!),
                          ),

                          // Recording status badge
                          if (_isRecording)
                            Positioned(
                              top: 16,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.85),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.fiber_manual_record,
                                          color: Colors.white, size: 14),
                                      const SizedBox(width: 6),
                                      Text(
                                        'REC ${_formatDuration(_recordDuration)}',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                          // Zoom controls bar (Pill, Zoom In/Out buttons, Quick Presets)
                          Positioned(
                            bottom: 12,
                            left: 16,
                            right: 16,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_showZoomSlider && _maxZoom > _minZoom)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Slider(
                                      value: _currentZoom,
                                      min: _minZoom,
                                      max: _maxZoom,
                                      activeColor: const Color(0xFF43E9B2),
                                      inactiveColor: Colors.white30,
                                      onChanged: (val) => _setZoom(val),
                                    ),
                                  ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.65),
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(
                                        color: Colors.white24, width: 0.5),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Zoom Out Button
                                      IconButton(
                                        icon: const Icon(Icons.remove,
                                            color: Colors.white, size: 18),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                            minWidth: 32, minHeight: 32),
                                        onPressed: _currentZoom > _minZoom
                                            ? _zoomOut
                                            : null,
                                      ),
                                      // Quick Presets: 1x, 2x, 3x
                                      _zoomPill('1.0x', 1.0),
                                      if (_maxZoom >= 2.0)
                                        _zoomPill('2.0x', 2.0),
                                      if (_maxZoom >= 3.0)
                                        _zoomPill('3.0x', 3.0),
                                      // Zoom In Button
                                      IconButton(
                                        icon: const Icon(Icons.add,
                                            color: Colors.white, size: 18),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                            minWidth: 32, minHeight: 32),
                                        onPressed: _currentZoom < _maxZoom
                                            ? _zoomIn
                                            : null,
                                      ),
                                      // Toggle fine slider
                                      IconButton(
                                        icon: Icon(
                                          _showZoomSlider
                                              ? Icons.tune
                                              : Icons.linear_scale,
                                          color: _showZoomSlider
                                              ? const Color(0xFF43E9B2)
                                              : Colors.white70,
                                          size: 18,
                                        ),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                            minWidth: 32, minHeight: 32),
                                        onPressed: () => setState(() =>
                                            _showZoomSlider = !_showZoomSlider),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : const Center(child: CircularProgressIndicator()),
          ),

          // Photo / Video Mode Selector
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _modeButton('PHOTO', CameraMode.photo),
                const SizedBox(width: 16),
                _modeButton('VIDEO', CameraMode.video),
              ],
            ),
          ),

          // Bottom Action Bar: Gallery, Shutter/Record, Camera Flip
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Gallery button
                IconButton(
                  iconSize: 32,
                  color: Colors.white,
                  onPressed: _isRecording ? null : _gallery,
                  icon: Icon(_mode == CameraMode.photo
                      ? Icons.photo_library_outlined
                      : Icons.video_library_outlined),
                ),

                // Shutter Button (Photo vs Video)
                GestureDetector(
                  onTap: _mode == CameraMode.photo
                      ? _capture
                      : (_isRecording ? _stopVideo : _startVideo),
                  child: Container(
                    width: 72,
                    height: 72,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _mode == CameraMode.video
                            ? Colors.redAccent
                            : Colors.white,
                        width: 4,
                      ),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        shape:
                            _isRecording ? BoxShape.rectangle : BoxShape.circle,
                        borderRadius:
                            _isRecording ? BorderRadius.circular(8) : null,
                        color: _mode == CameraMode.video
                            ? Colors.red
                            : (_taking ? Colors.grey : Colors.white),
                      ),
                    ),
                  ),
                ),

                // Camera Flip button
                IconButton(
                  iconSize: 32,
                  color: Colors.white,
                  onPressed: _cams.length < 2 || _isRecording
                      ? null
                      : () {
                          _idx = (_idx + 1) % _cams.length;
                          _open();
                        },
                  icon: const Icon(Icons.flip_camera_android_outlined),
                ),
              ],
            ),
          ),

          // Next / Review draft navigation if photos/videos exist
          if (context.watch<AppState>().draft.photos.isNotEmpty ||
              context.watch<AppState>().draft.videos.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextButton.icon(
                icon: const Icon(Icons.arrow_forward, color: Color(0xFF43E9B2)),
                onPressed: () => Navigator.pushNamed(context, '/photos'),
                label: Text(
                  '${context.watch<AppState>().draft.photos.length} photo(s), '
                  '${context.watch<AppState>().draft.videos.length} video(s) - ${s('next')}',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _zoomPill(String label, double zoom) {
    final active = (_currentZoom - zoom).abs() < 0.2;
    return GestureDetector(
      onTap: () => _setZoom(zoom),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF43E9B2) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.black : Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _modeButton(String title, CameraMode targetMode) {
    final active = _mode == targetMode;
    return GestureDetector(
      onTap: _isRecording ? null : () => setState(() => _mode = targetMode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? const Color(0xFF43E9B2) : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: active ? Colors.white : Colors.white54,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
            letterSpacing: 1.2,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
