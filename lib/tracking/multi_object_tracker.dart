import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../vision/ensemble/ensemble_engine.dart';
import '../vision/ensemble/unified_detection.dart';

/// Lifecycle state of a tracked physical object.
enum TrackState {
  tentative,
  active,
  lost,
  removed,
}

/// A persistent tracked physical object across video frames.
class MultiTrackObject {
  MultiTrackObject({
    required this.trackId,
    required this.className,
    required this.box,
    required this.confidence,
    required this.colorHex,
    required this.contributingModelIds,
    required this.agreementCount,
    required this.activeModelCount,
    required this.firstSeenTimestamp,
    required this.lastSeenTimestamp,
    this.framesSeen = 1,
    this.missedFrames = 0,
    this.state = TrackState.tentative,
  });

  final int trackId;
  String className;
  Rect box;
  double confidence;
  int colorHex;
  List<String> contributingModelIds;
  int agreementCount;
  int activeModelCount;
  final int firstSeenTimestamp;
  int lastSeenTimestamp;
  int framesSeen;
  int missedFrames;
  TrackState state;

  String get displayId => '#${trackId.toString().padLeft(2, '0')}';

  double get agreementRatio =>
      activeModelCount > 0 ? (agreementCount / activeModelCount).clamp(0.0, 1.0) : 1.0;

  String get agreementBadge => '$agreementCount/$activeModelCount';

  Offset get center => Offset(
        (box.left + box.right) / 2.0,
        (box.top + box.bottom) / 2.0,
      );
}

/// MultiObjectTracker provides persistent ID tracking, track state confirmation,
/// trajectory smoothing (EMA), and missed-frame occlusion handling.
class MultiObjectTracker {
  MultiObjectTracker({
    this.confirmationFrames = 1,
    this.maxMissedFrames = 8,
    this.iouMatchThreshold = 0.25,
    this.smoothingAlpha = 0.70,
  });

  final int confirmationFrames;
  final int maxMissedFrames;
  final double iouMatchThreshold;
  final double smoothingAlpha;

  int _nextTrackId = 1;
  final List<MultiTrackObject> _tracks = [];

  List<MultiTrackObject> get activeTracks =>
      _tracks.where((t) => t.state == TrackState.active).toList();

  List<MultiTrackObject> get allTracks => List.unmodifiable(_tracks);

  /// Update tracker with newly fused unified detections from the EnsembleEngine.
  List<MultiTrackObject> update(
    List<UnifiedDetection> detections, {
    int timestamp = 0,
  }) {
    final matchedDetectionIndices = <int>{};
    final matchedTrackIndices = <int>{};

    // 1. Match existing tracks to candidate detections using IoU and centroid proximity
    for (var tIdx = 0; tIdx < _tracks.length; tIdx++) {
      final track = _tracks[tIdx];
      if (track.state == TrackState.removed) continue;

      int bestDetIdx = -1;
      double bestScore = 0.0;

      for (var dIdx = 0; dIdx < detections.length; dIdx++) {
        if (matchedDetectionIndices.contains(dIdx)) continue;
        final det = detections[dIdx];

        if (det.className.toLowerCase() != track.className.toLowerCase()) {
          continue;
        }

        final iou = EnsembleEngine.computeIoU(track.box, det.box);
        final dist = (track.center - det.center).distance;
        final proximityScore = math.max(0.0, 1.0 - (dist / 0.5));
        final combinedScore = 0.7 * iou + 0.3 * proximityScore;

        if (combinedScore > iouMatchThreshold && combinedScore > bestScore) {
          bestScore = combinedScore;
          bestDetIdx = dIdx;
        }
      }

      if (bestDetIdx >= 0) {
        matchedDetectionIndices.add(bestDetIdx);
        matchedTrackIndices.add(tIdx);

        final det = detections[bestDetIdx];
        _updateTrack(track, det, timestamp);
      } else {
        // Track was missed in this frame
        track.missedFrames++;
        if (track.missedFrames > maxMissedFrames) {
          track.state = TrackState.removed;
        } else {
          track.state = TrackState.lost;
        }
      }
    }

    // 2. Create new tentative tracks for unmatched candidate detections
    for (var dIdx = 0; dIdx < detections.length; dIdx++) {
      if (!matchedDetectionIndices.contains(dIdx)) {
        final det = detections[dIdx];
        _tracks.add(
          MultiTrackObject(
            trackId: _nextTrackId++,
            className: det.className,
            box: det.box,
            confidence: det.confidence,
            colorHex: det.colorHex,
            contributingModelIds: det.contributingModelIds,
            agreementCount: det.agreementCount,
            activeModelCount: det.activeModelCount,
            firstSeenTimestamp: timestamp,
            lastSeenTimestamp: timestamp,
            framesSeen: 1,
            missedFrames: 0,
            state: confirmationFrames <= 1
                ? TrackState.active
                : TrackState.tentative,
          ),
        );
      }
    }

    // 3. Remove expired tracks
    _tracks.removeWhere((t) => t.state == TrackState.removed);

    // Return all confirmed active tracks (or tentative if confirmed count is met)
    return _tracks.where((t) => t.state == TrackState.active || t.framesSeen >= confirmationFrames).toList();
  }

  void _updateTrack(MultiTrackObject track, UnifiedDetection det, int timestamp) {
    track.framesSeen++;
    track.missedFrames = 0;
    track.lastSeenTimestamp = timestamp;
    track.className = det.className;
    track.colorHex = det.colorHex;
    track.contributingModelIds = det.contributingModelIds;
    track.agreementCount = det.agreementCount;
    track.activeModelCount = det.activeModelCount;

    // Exponential Moving Average (EMA) box smoothing
    final alpha = smoothingAlpha;
    final smoothedLeft = alpha * det.box.left + (1.0 - alpha) * track.box.left;
    final smoothedTop = alpha * det.box.top + (1.0 - alpha) * track.box.top;
    final smoothedRight = alpha * det.box.right + (1.0 - alpha) * track.box.right;
    final smoothedBottom = alpha * det.box.bottom + (1.0 - alpha) * track.box.bottom;

    track.box = Rect.fromLTRB(smoothedLeft, smoothedTop, smoothedRight, smoothedBottom);
    track.confidence = alpha * det.confidence + (1.0 - alpha) * track.confidence;

    // Transition from tentative to active
    if (track.framesSeen >= confirmationFrames) {
      track.state = TrackState.active;
    }
  }

  /// Reset all tracks and reset ID counter.
  void reset() {
    _tracks.clear();
    _nextTrackId = 1;
  }
}
