import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../config/mobile_config.dart';
import '../core/app_logger.dart';
import '../core/result.dart';
import '../models/analysis.dart';
import '../models/evidence.dart';
import '../models/observation.dart';
import '../repositories/observation_repository.dart';
import '../services/location_service.dart';
import '../services/mobile_camera_service.dart';
import 'portal_services.dart';
import 'widgets.dart';

/// One-screen field flow: locate → capture or attach → review the assessment →
/// submit. Everything is written locally first, and submission queues itself
/// when the backend cannot be reached (§20, §22, §29, §44).
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key, this.observationId});

  /// Set when resuming an existing draft instead of starting a new one.
  final String? observationId;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final TextEditingController _description = TextEditingController();

  Observation? _draft;
  List<Evidence> _evidence = const <Evidence>[];
  LocationFix? _fix;
  GpsOutcome? _gpsOutcome;
  String _category = DefectCategoryCatalog.pothole.id;
  bool _busyLocation = false;
  bool _busyIngest = false;
  bool _submitting = false;
  QualityReport? _lastQuality;
  AnalysisResult? _lastAnalysis;
  DuplicateMatch? _duplicate;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    unawaited(MobileCameraService.instance.stop());
    _description.dispose();
    super.dispose();
  }

  /// The composition root. [PortalScope.read] is used because this screen is
  /// also touched from `initState()`, where dependency registration is illegal.
  PortalServices get _services => PortalScope.read(context);

  /// Restores a draft when one was requested; a fresh report starts empty and
  /// refuses to accept evidence until a real position exists.
  Future<void> _bootstrap() async {
    final String? id = widget.observationId;
    if (id == null) return;
    final Observation? existing = _services.database.observationById(id);
    if (existing == null || !mounted) return;
    setState(() {
      _draft = existing;
      _category = existing.category;
      _description.text = existing.description;
      _fix = existing.location;
      _gpsOutcome = GpsOutcome.acquired;
      _evidence = _services.database.evidenceForObservation(id);
    });
  }

  void _show(String message) {
    if (!mounted) return;
    setState(() => _notice = message);
  }

  /// §20 — position comes from the device sensors, never from a text field.
  ///
  /// The acquisition is fully guarded so [_busyLocation] can never stay
  /// latched: a platform exception previously disabled the GPS button for the
  /// remaining life of the screen with no way to recover.
  Future<void> acquireLocation() async {
    setState(() => _busyLocation = true);
    try {
      final GpsOutcome outcome = await _services.location.acquireBestFix();
      final LocationFix? fix = _services.location.best;
      if (!mounted) return;
      setState(() {
        _gpsOutcome = outcome;
        _fix = fix;
        _notice = outcome == GpsOutcome.acquired
            ? null
            : '${outcome.label}. A report cannot be created without a real '
                'position — turn on location or move to open sky and retry.';
      });
      if (fix != null && _draft == null) await _createDraft(fix);
    } catch (error) {
      AppLog.e('Capture', 'Location acquisition failed: $error');
      if (!mounted) return;
      setState(() {
        _gpsOutcome = GpsOutcome.unavailable;
        _notice = 'The device location could not be read. Check that location '
            'services are switched on, then try again.';
      });
    } finally {
      if (mounted) setState(() => _busyLocation = false);
    }
  }

  Future<void> _createDraft(LocationFix fix) async {
    final Observation draft = await _services.repository.createDraft(
      location: fix,
      category: _category,
      description: _description.text.trim(),
    );
    if (!mounted) return;
    setState(() => _draft = draft);
  }

  // ---------------------------------------------------------------------------
  // Camera (§7/§8): plugin-backed preview, capture and honest failure states
  // ---------------------------------------------------------------------------

  Future<void> startCamera() async {
    final MobileCameraService camera = MobileCameraService.instance;
    final bool ready = await camera.initialize();
    if (!ready) _show(camera.lastError ?? 'The camera could not be started.');
  }

  Future<void> takePhoto() async {
    final Observation? draft = _draft;
    if (draft == null) {
      _show('Get a location fix first — reports must carry a position.');
      return;
    }
    final MobileCameraService camera = MobileCameraService.instance;
    if (!camera.isInitialized) {
      final bool ready = await camera.initialize();
      if (!ready) {
        _show(camera.lastError ?? 'The camera could not be started.');
        return;
      }
    }
    setState(() => _busyIngest = true);
    CameraCapture? capture;
    try {
      capture = await camera.capturePhoto();
    } catch (error, stack) {
      AppLog.e('Capture', 'takePhoto failed: $error');
      AppLog.d('Capture', 'takePhoto stack: $stack');
    }
    if (capture == null) {
      if (!mounted) return;
      _show(camera.lastError ?? 'The photo was not captured.');
      return;
    }
    // _ingest owns the busy flag from here so it is cleared exactly once.
    await _ingest(
      draft: draft,
      file: capture.file,
      type: EvidenceType.image,
      captureSource: 'camera',
      capturedAt: capture.capturedAt,
    );
  }

  // ---------------------------------------------------------------------------
  // Evidence ingestion (§13/§17/§18/§40)
  // ---------------------------------------------------------------------------

  Future<void> pickFromGallery({bool video = false}) async {
    final Observation? draft = _draft;
    if (draft == null) {
      _show('Get a location fix first — reports must carry a position.');
      return;
    }
    if (_evidence.length >= MobileConfig.maxEvidencePerObservation) {
      _show('This report already holds the maximum of '
          '${MobileConfig.maxEvidencePerObservation} evidence items.');
      return;
    }
    final PlatformFile? picked = await FilePicker.pickFile(
      type: video ? FileType.video : FileType.image,
    );
    final String? path = picked?.path;
    if (path == null) return;
    await _ingest(
      draft: draft,
      file: File(path),
      type: video ? EvidenceType.video : EvidenceType.image,
      captureSource: 'gallery',
    );
  }

  Future<void> _ingest({
    required Observation draft,
    required File file,
    required EvidenceType type,
    required String captureSource,
    DateTime? capturedAt,
  }) async {
    if (_evidence.length >= MobileConfig.maxEvidencePerObservation) {
      _show('This report already holds the maximum of '
          '${MobileConfig.maxEvidencePerObservation} evidence items.');
      return;
    }
    setState(() => _busyIngest = true);
    try {
      final Result<EvidenceIngest> result =
          await _services.repository.ingestEvidence(
        observationId: draft.id,
        file: file,
        type: type,
        role:
            _evidence.isEmpty ? EvidenceRole.closeUp : EvidenceRole.additional,
        captureSource: captureSource,
        capturedAt: capturedAt,
        location: _fix,
      );
      if (!mounted) return;
      if (result is Err<EvidenceIngest>) {
        _show(result.failure.message);
        return;
      }
      final EvidenceIngest ingest = result.value;
      _lastQuality = ingest.quality;
      _lastAnalysis = ingest.analysis;

      Observation current =
          _services.database.observationById(draft.id) ?? draft;
      final AnalysisResult analysis = ingest.analysis;
      if (analysis.hasInfrastructurePrediction &&
          !current.categoryCorrectedByUser &&
          analysis.suggestedCategoryId != current.category) {
        current = await _services.repository.reassess(
          observation: current,
          category: analysis.suggestedCategoryId!,
          aiConfidence: analysis.confidence,
          screening: analysis.screening,
        );
        _category = current.category;
      }
      if (!mounted) return;
      setState(() {
        _draft = current;
        _evidence = _services.database.evidenceForObservation(current.id);
        _duplicate = _services.repository.checkDuplicates(current);
        _notice = ingest.quality.grade == QualityGrade.poor
            ? 'Image quality is low: '
                '${ingest.quality.findings.map((QualityFinding f) => f.message).join(' ')} '
                '— a retake is recommended, but the evidence is saved.'
            : null;
      });
    } catch (error, stack) {
      // Never leave the ingest spinner latched: the user must always be able
      // to retry after a storage or codec failure (§13/§17).
      AppLog.e('Capture', 'Evidence ingest failed: $error');
      AppLog.d('Capture', 'Evidence ingest stack: $stack');
      if (mounted) {
        _show('That file could not be attached. Check free storage and retry.');
      }
    } finally {
      if (mounted) setState(() => _busyIngest = false);
    }
  }

  /// Changing the category re-runs the real assessment engines (§38/§39).
  Future<void> changeCategory(String categoryId) async {
    final Observation? draft = _draft;
    setState(() => _category = categoryId);
    if (draft == null) return;
    final Observation updated = await _services.repository.reassess(
      observation: draft,
      category: categoryId,
      aiConfidence: _lastAnalysis?.confidence,
      screening: _lastAnalysis?.screening ?? VisualScreening.empty,
      categoryCorrectedByUser: true,
    );
    if (!mounted) return;
    setState(() {
      _draft = updated;
      _duplicate = _services.repository.checkDuplicates(updated);
    });
  }

  // ---------------------------------------------------------------------------
  // Submission (§29/§31)
  // ---------------------------------------------------------------------------

  Future<void> submit() async {
    final Observation? draft = _draft;
    if (draft == null) return;
    if (_evidence.isEmpty) {
      _show('Add at least one photo or video before submitting.');
      return;
    }
    setState(() => _submitting = true);
    Result<Observation> result;
    try {
      result = await _services.repository.submit(
        observation: draft,
        descriptionOverride: _description.text.trim(),
      );
    } catch (error, stack) {
      // A thrown submission must not latch the button: the report is still a
      // local draft and the inspector has to be able to retry or discard it.
      AppLog.e('Capture', 'Submit failed: $error');
      AppLog.d('Capture', 'Submit stack: $stack');
      if (mounted) {
        _show('The report could not be submitted. It is still saved on this '
            'device — try again.');
      }
      return;
    } finally {
      // The camera is released on every exit path, successful or not (§57).
      await MobileCameraService.instance.stop();
      if (mounted) setState(() => _submitting = false);
    }
    if (!mounted) return;
    if (result is Err<Observation>) {
      _show(result.failure.message);
      return;
    }
    final Observation submitted = result.value;
    final bool confirmed =
        submitted.syncState == SyncState.synced || submitted.serverId != null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          confirmed
              ? 'Report submitted and confirmed by the backend.'
              : 'Report saved on this device. It uploads automatically once '
                  'the backend is reachable.',
        ),
      ),
    );
    if (widget.observationId != null) {
      Navigator.of(context).maybePop();
      return;
    }
    _description.clear();
    setState(() {
      _draft = null;
      _evidence = const <Evidence>[];
      _lastAnalysis = null;
      _lastQuality = null;
      _duplicate = null;
      _notice = null;
    });
    final LocationFix? fix = _fix;
    if (fix != null) await _createDraft(fix);
  }

  /// Only drafts may be discarded — submitted reports are never deleted (§103).
  Future<void> discardDraft() async {
    final Observation? draft = _draft;
    if (draft == null) return;
    final Result<void> result =
        await _services.repository.discardDraft(draft.id);
    await MobileCameraService.instance.stop();
    if (!mounted) return;
    if (result is Err<void>) {
      _show(result.failure.message);
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Observation? draft = _draft;
    return Scaffold(
      appBar: AppBar(
        title: Text(draft == null ? 'New report' : 'Report ${draft.id}'),
        actions: <Widget>[
          if (draft != null && draft.status == ObservationStatus.draft)
            IconButton(
              tooltip: 'Discard this draft',
              onPressed: _submitting ? null : discardDraft,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: <Widget>[
          if (_busyIngest) const LinearProgressIndicator(minHeight: 2),
          SectionCard(
            title: 'Position',
            icon: Icons.gps_fixed,
            subtitle: 'Required before anything can be captured',
            trailing: _busyLocation
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (_fix == null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _gpsOutcome == null
                            ? 'Tap to acquire a position from the device.'
                            : 'Last attempt: ${_gpsOutcome!.label}',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: _busyLocation ? null : acquireLocation,
                        icon: const Icon(Icons.my_location),
                        label: const Text('Get location'),
                      ),
                    ],
                  )
                else
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '${_fix!.latitude.toStringAsFixed(6)}, '
                          '${_fix!.longitude.toStringAsFixed(6)} · '
                          '±${_fix!.accuracyMeters.toStringAsFixed(1)} m',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      TextButton(
                        onPressed: _busyLocation ? null : acquireLocation,
                        child: const Text('Re-acquire'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          CameraCard(onCapture: takePhoto, onOpen: startCamera),
          SectionCard(
            title: 'Evidence (${_evidence.length}/'
                '${MobileConfig.maxEvidencePerObservation})',
            icon: Icons.photo_library_outlined,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IconButton(
                  tooltip: 'Attach a photo from the gallery',
                  onPressed: draft == null || _busyIngest
                      ? null
                      : () => pickFromGallery(),
                  icon: const Icon(Icons.image_outlined),
                ),
                IconButton(
                  tooltip: 'Attach a video from the gallery',
                  onPressed: draft == null || _busyIngest
                      ? null
                      : () => pickFromGallery(video: true),
                  icon: const Icon(Icons.movie_outlined),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (_evidence.isEmpty)
                  Text(
                    draft == null
                        ? 'Acquire a position to start the report.'
                        : 'No evidence yet. Capture a photo — a close-up plus '
                            'a context view works best.',
                    style: theme.textTheme.bodySmall,
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _evidence
                        .map(
                          (Evidence e) => EvidenceThumb(
                            path: e.listImagePath,
                            isVideo: e.isVideo,
                            size: 72,
                          ),
                        )
                        .toList(),
                  ),
                if (_lastQuality != null && _evidence.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    children: <Widget>[
                      QualityPill(
                        grade: _lastQuality!.grade,
                        findings: _lastQuality!.findings,
                      ),
                      Pill(
                        label: '${_lastQuality!.width}×${_lastQuality!.height}',
                        color: const Color(0xFF8A8F98),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          SectionCard(
            title: 'Category',
            icon: Icons.category_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  isExpanded: true,
                  items: DefectCategoryCatalog.all
                      .map(
                        (DefectCategory c) => DropdownMenuItem<String>(
                          value: c.id,
                          child: Text(c.label),
                        ),
                      )
                      .toList(),
                  onChanged: draft == null
                      ? null
                      : (String? value) {
                          if (value != null) changeCategory(value);
                        },
                  decoration: const InputDecoration(labelText: 'Defect type'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _description,
                  maxLines: 3,
                  maxLength: 400,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    hintText: 'Size, standing water, traffic impact…',
                  ),
                ),
                if (draft != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      SeverityPill(level: draft.severity),
                      PriorityPill(level: draft.priority),
                      Pill(
                        label: 'Severity '
                            '${(draft.severityScore * 100).round()}/100',
                        color: const Color(0xFF8A8F98),
                      ),
                      Pill(
                        label: 'Priority '
                            '${(draft.priorityScore * 100).round()}/100',
                        color: const Color(0xFF8A8F98),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Severity and priority are calculated from the category, '
                    'evidence count and measured image signals.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor),
                  ),
                ],
              ],
            ),
          ),
          AnalysisCard(analysis: _lastAnalysis),
          if (_duplicate != null)
            SectionCard(
              title: 'Possible duplicate',
              icon: Icons.copy_all_outlined,
              child: Text(
                '${_duplicate!.summary} ${_duplicate!.reasons.join(' · ')} '
                'Submit anyway if this really is a different defect.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (_notice != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Text(
                _notice!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: const Color(0xFFF76B15)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _submitting ? null : submit,
                icon: const Icon(Icons.upload_file),
                label: Text(
                  _submitting ? 'Saving…' : 'Submit report',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// On-device analysis panel. It reports exactly what the model did — including
/// the honest case where it could not run at all (§37).
class AnalysisCard extends StatelessWidget {
  const AnalysisCard({super.key, this.analysis});

  final AnalysisResult? analysis;

  @override
  Widget build(BuildContext context) {
    final AnalysisResult? result = analysis;
    if (result == null) return const SizedBox.shrink();
    final ThemeData theme = Theme.of(context);
    final String detail = result.rawSummary ??
        result.failureReason ??
        'No model output for this capture.';
    return SectionCard(
      title: result.availabilityLabel,
      icon: Icons.memory,
      trailing: result.confidence == null
          ? null
          : Pill(
              label: '${(result.confidence! * 100).round()}%',
              color: const Color(0xFF3B9EFF),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(detail, style: theme.textTheme.bodySmall),
          if (result.modelVersion != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              'Model: ${result.modelVersion} · '
              '${result.inferenceMs ?? 0} ms',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.hintColor),
            ),
          ],
          if (result.objects.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              result.objects
                  .map((ModelObject o) =>
                      '${o.label} ${(o.confidence * 100).round()}%')
                  .join(' · '),
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'Measured surface signals — anomaly '
            '${(result.screening.surfaceAnomalyIndex * 100).round()}%, '
            'sharpness ${result.screening.laplacianVariance.toStringAsFixed(0)}'
            ', edges ${(result.screening.edgeDensity * 100).round()}%',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.hintColor),
          ),
        ],
      ),
    );
  }
}

/// Camera panel backed by the plugin-driven [MobileCameraService]. It never
/// claims the camera works when the plugin or hardware failed (§7/§8).
class CameraCard extends StatelessWidget {
  const CameraCard({super.key, this.onCapture, this.onOpen});

  final Future<void> Function()? onCapture;
  final Future<void> Function()? onOpen;

  @override
  Widget build(BuildContext context) {
    final MobileCameraService camera = MobileCameraService.instance;
    final ThemeData theme = Theme.of(context);
    return SectionCard(
      title: 'Camera',
      icon: Icons.videocam_outlined,
      trailing: camera.capabilities.hasMultiple
          ? IconButton(
              tooltip: 'Switch camera',
              onPressed: () => camera.switchCamera(),
              icon: const Icon(Icons.cameraswitch_outlined),
            )
          : null,
      child: ListenableBuilder(
        listenable: camera,
        builder: (BuildContext context, Widget? child) {
          if (camera.isInitializing) {
            return const Row(
              children: <Widget>[
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text('Preparing the camera…'),
              ],
            );
          }
          final CameraController? controller = camera.controller;
          if (controller == null || !controller.value.isInitialized) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  camera.lastError ??
                      'The camera is off. Open it to capture evidence.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('Open camera'),
                ),
              ],
            );
          }
          return Column(
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 220,
                  child: Center(
                    child: CameraPreview(controller),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  IconButton.outlined(
                    tooltip: 'Torch',
                    onPressed: camera.capabilities.hasFlash
                        ? () => camera.cycleFlash()
                        : null,
                    icon: Icon(
                      camera.flashMode == FlashMode.off
                          ? Icons.flash_off
                          : Icons.flash_on,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: camera.isCapturing ? null : onCapture,
                    icon: const Icon(Icons.photo_camera),
                    label: Text(
                      camera.isCapturing ? 'Capturing…' : 'Capture photo',
                    ),
                  ),
                  IconButton.outlined(
                    tooltip: 'Zoom in',
                    onPressed: () => camera.setZoom(
                      (camera.zoom + 0.5).clamp(
                        camera.capabilities.minZoom,
                        camera.capabilities.maxZoom,
                      ),
                    ),
                    icon: const Icon(Icons.zoom_in),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

