import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class PotholeMobileApp extends StatelessWidget {
  const PotholeMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'InfraVision Pothole AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF43E9B2),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const PotholeCameraScreen(),
    );
  }
}

class PotholeCameraScreen extends StatefulWidget {
  const PotholeCameraScreen({super.key});

  @override
  State<PotholeCameraScreen> createState() => _PotholeCameraScreenState();
}

class _PotholeCameraScreenState extends State<PotholeCameraScreen> {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  bool _loading = true;
  String? _error;
  double _confidence = .55;
  bool _aiEnabled = true;

  @override
  void initState() {
    super.initState();
    _startCamera(CameraLensDirection.back);
  }

  Future<void> _startCamera(CameraLensDirection direction) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _cameras = await availableCameras();
      final selected = _cameras.firstWhere(
        (camera) => camera.lensDirection == direction,
        orElse: () => _cameras.first,
      );
      final next = CameraController(
        selected,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await next.initialize();
      final previous = _controller;
      _controller = next;
      await previous?.dispose();
      if (mounted) {
        setState(() => _loading = false);
      }
    } on CameraException catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.description ?? error.code;
        });
      }
    } catch (error) {
      if (mounted) setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _switchCamera() async {
    final active = _controller?.description.lensDirection;
    await _startCamera(
      active == CameraLensDirection.back
          ? CameraLensDirection.front
          : CameraLensDirection.back,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: const Color(0xFF08100F),
      body: SafeArea(
        child: Column(
          children: [
            _Header(onStudio: () => _showStudio(context)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_loading)
                        const Center(child: CircularProgressIndicator())
                      else if (_error != null)
                        _CameraError(message: _error!)
                      else if (controller != null && controller.value.isInitialized)
                        CameraPreview(controller),
                      const _RoadGuide(),
                      Positioned(
                        top: 14,
                        left: 14,
                        child: _StatusChip(enabled: _aiEnabled),
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: IconButton.filledTonal(
                          tooltip: 'Switch front or rear camera',
                          onPressed: _loading ? null : _switchCamera,
                          icon: const Icon(Icons.cameraswitch_outlined),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _Controls(
              aiEnabled: _aiEnabled,
              confidence: _confidence,
              onAiChanged: (value) => setState(() => _aiEnabled = value),
              onConfidenceChanged: (value) => setState(() => _confidence = value),
            ),
          ],
        ),
      ),
    );
  }

  void _showStudio(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF10201D),
      showDragHandle: true,
      builder: (context) => const Padding(
        padding: EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Model Studio', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            SizedBox(height: 12),
            Text('Pothole model: validation in progress'),
            SizedBox(height: 8),
            Text(
              'Live camera, front/rear switching and confidence controls are ready. A real detector is enabled only after its validation model is bundled, so this app never invents detections.',
              style: TextStyle(color: Color(0xFFB7C7C2)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onStudio});
  final VoidCallback onStudio;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
        child: Row(children: [
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('InfraVision', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              Text('Pothole AI • on-device', style: TextStyle(color: Color(0xFF9AB5AC))),
            ]),
          ),
          TextButton.icon(onPressed: onStudio, icon: const Icon(Icons.tune), label: const Text('Studio')),
        ]),
      );
}

class _Controls extends StatelessWidget {
  const _Controls({required this.aiEnabled, required this.confidence, required this.onAiChanged, required this.onConfidenceChanged});
  final bool aiEnabled;
  final double confidence;
  final ValueChanged<bool> onAiChanged;
  final ValueChanged<double> onConfidenceChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        decoration: const BoxDecoration(color: Color(0xFF10201D)),
        child: Column(children: [
          Row(children: [
            const Icon(Icons.memory_outlined, color: Color(0xFF43E9B2)),
            const SizedBox(width: 10),
            const Expanded(child: Text('Pothole detector')),
            Switch(value: aiEnabled, onChanged: onAiChanged),
          ]),
          Row(children: [
            const Text('Confidence'),
            Expanded(child: Slider(value: confidence, min: .3, max: .9, divisions: 12, label: '${(confidence * 100).round()}%', onChanged: onConfidenceChanged)),
            SizedBox(width: 42, child: Text('${(confidence * 100).round()}%')),
          ]),
        ]),
      );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.enabled});
  final bool enabled;
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(color: const Color(0xDD10201D), borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(enabled ? 'AI ARMED' : 'AI PAUSED', style: TextStyle(color: enabled ? const Color(0xFF43E9B2) : Colors.white70, fontWeight: FontWeight.w700)),
        ),
      );
}

class _RoadGuide extends StatelessWidget {
  const _RoadGuide();
  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Center(child: Container(width: 180, height: 120, decoration: BoxDecoration(border: Border.all(color: const Color(0x885DEFC0), width: 2), borderRadius: BorderRadius.circular(12)))),
      );
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text('Camera unavailable\n$message', textAlign: TextAlign.center),
        ),
      );
}
