import 'package:flutter/material.dart';
import '../vision/lightweight_object_detector.dart';

/// A tracked object with a persistent track ID, smoothed coordinates, and velocity.
class TrackedObject {
  TrackedObject({
    required this.trackId,
    required this.box,
    required this.label,
    required this.confidence,
    required this.colorHex,
    required this.center,
    this.framesTracked = 1,
    this.missedFrames = 0,
    this.velocity = Offset.zero,
  });

  /// Unique persistent ID across video frames (e.g. 1, 2, 3).
  final int trackId;

  /// Smoothed bounding box in normalized coordinates (0..1).
  Rect box;

  /// Current classified label.
  String label;

  /// Detection confidence (0..1).
  double confidence;

  /// Hex color styling.
  final int colorHex;

  /// Center point in normalized coordinates.
  Offset center;

  /// Total number of consecutive frames this object has been tracked.
  int framesTracked;

  /// Number of frames since this track was last directly detected.
  int missedFrames;

  /// Movement velocity in normalized frame space per frame.
  Offset velocity;

  /// Formatted track display tag (e.g. "#01").
  String get displayId => '#${trackId.toString().padLeft(2, '0')}';
}

/// Real-time Multi-Object Tracker (IoU + Centroid Proximity with Kalman/EMA smoothing).
class ObjectTracker {
  ObjectTracker({
    this.iouThreshold = 0.25,
    this.distanceThreshold = 0.18,
    this.maxMissedFrames = 6,
    this.smoothingFactor = 0.65,
  });

  final double iouThreshold;
  final double distanceThreshold;
  final int maxMissedFrames;
  final double smoothingFactor;

  final List<TrackedObject> _tracks = [];
  int _nextTrackId = 1;

  /// Active tracked objects.
  List<TrackedObject> get activeTracks => List.unmodifiable(_tracks);

  /// Update tracker state with new detections from the current frame.
  List<TrackedObject> update(List<VisionDetection> detections) {
    // 1. Predict position based on previous velocity
    for (final track in _tracks) {
      track.center += track.velocity * 0.5;
      track.box = Rect.fromCenter(
        center: track.center,
        width: track.box.width,
        height: track.box.height,
      );
      track.missedFrames++;
    }

    final matchedDetections = List<bool>.filled(detections.length, false);
    final matchedTracks = List<bool>.filled(_tracks.length, false);

    // 2. Compute cost matrix & match tracks to detections (highest IoU / lowest distance)
    for (var t = 0; t < _tracks.length; t++) {
      var bestIoU = 0.0;
      var bestDetIdx = -1;

      final track = _tracks[t];
      final trackCenter = Offset(
        (track.box.left + track.box.right) / 2.0,
        (track.box.top + track.box.bottom) / 2.0,
      );

      for (var d = 0; d < detections.length; d++) {
        if (matchedDetections[d]) continue;

        final det = detections[d];
        final iou = _calculateIoU(track.box, det.box);

        final detCenter = det.center ??
            Offset(
              (det.box.left + det.box.right) / 2.0,
              (det.box.top + det.box.bottom) / 2.0,
            );

        final dist = (trackCenter - detCenter).distance;

        if (iou > bestIoU && iou >= iouThreshold) {
          bestIoU = iou;
          bestDetIdx = d;
        } else if (bestIoU == 0.0 && dist <= distanceThreshold && (track.label == det.label || track.label == 'object' || det.label == 'object')) {
          bestDetIdx = d;
        }
      }

      if (bestDetIdx != -1) {
        final det = detections[bestDetIdx];
        matchedDetections[bestDetIdx] = true;
        matchedTracks[t] = true;

        // Smooth bounding box using Exponential Moving Average
        final smoothedLeft = track.box.left * smoothingFactor + det.box.left * (1 - smoothingFactor);
        final smoothedTop = track.box.top * smoothingFactor + det.box.top * (1 - smoothingFactor);
        final smoothedRight = track.box.right * smoothingFactor + det.box.right * (1 - smoothingFactor);
        final smoothedBottom = track.box.bottom * smoothingFactor + det.box.bottom * (1 - smoothingFactor);

        final newCenter = Offset((smoothedLeft + smoothedRight) / 2.0, (smoothedTop + smoothedBottom) / 2.0);
        final newVelocity = newCenter - track.center;

        track.box = Rect.fromLTRB(smoothedLeft, smoothedTop, smoothedRight, smoothedBottom);
        track.center = newCenter;
        track.velocity = track.velocity * 0.4 + newVelocity * 0.6;
        track.label = det.label;
        track.confidence = track.confidence * 0.3 + det.confidence * 0.7;
        track.framesTracked++;
        track.missedFrames = 0;
      }
    }

    // 3. Create new tracks for unmatched detections
    for (var d = 0; d < detections.length; d++) {
      if (!matchedDetections[d]) {
        final det = detections[d];
        final center = det.center ??
            Offset(
              (det.box.left + det.box.right) / 2.0,
              (det.box.top + det.box.bottom) / 2.0,
            );

        _tracks.add(TrackedObject(
          trackId: _nextTrackId++,
          box: det.box,
          label: det.label,
          confidence: det.confidence,
          colorHex: det.colorHex,
          center: center,
          framesTracked: 1,
          missedFrames: 0,
        ));
      }
    }

    // 4. Remove stale tracks
    _tracks.removeWhere((track) => track.missedFrames > maxMissedFrames);

    // Keep active tracks (filter out tracks that missed frames if not yet mature)
    return _tracks.where((t) => t.missedFrames == 0 || t.framesTracked >= 3).toList();
  }

  /// Reset all tracked state.
  void reset() {
    _tracks.clear();
    _nextTrackId = 1;
  }

  double _calculateIoU(Rect a, Rect b) {
    final intersection = a.intersect(b);
    if (intersection.width <= 0 || intersection.height <= 0) return 0.0;
    final intersectionArea = intersection.width * intersection.height;
    final unionArea = (a.width * a.height) + (b.width * b.height) - intersectionArea;
    if (unionArea <= 0) return 0.0;
    return intersectionArea / unionArea;
  }
}
