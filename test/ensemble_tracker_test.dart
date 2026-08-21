import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infravision/tracking/multi_object_tracker.dart';
import 'package:infravision/vision/ensemble/ensemble_engine.dart';
import 'package:infravision/vision/ensemble/unified_detection.dart';
import 'package:infravision/vision/models/model_metadata.dart';
import 'package:infravision/vision/models/vision_model.dart';

void main() {
  group('EnsembleEngine', () {
    test('computes IoU correctly for identical, overlapping and disjoint boxes', () {
      const boxA = Rect.fromLTWH(0.2, 0.2, 0.4, 0.4);
      const boxB = Rect.fromLTWH(0.2, 0.2, 0.4, 0.4);
      expect(EnsembleEngine.computeIoU(boxA, boxB), closeTo(1.0, 0.001));

      const boxDisjoint = Rect.fromLTWH(0.7, 0.7, 0.2, 0.2);
      expect(EnsembleEngine.computeIoU(boxA, boxDisjoint), 0.0);

      const boxPartial = Rect.fromLTWH(0.4, 0.2, 0.4, 0.4);
      final iou = EnsembleEngine.computeIoU(boxA, boxPartial);
      expect(iou, greaterThan(0.2));
      expect(iou, lessThan(0.5));
    });

    test('fuses overlapping detections from Model A and Model B with agreement count', () {
      final engine = EnsembleEngine(iouThreshold: 0.40);

      const detA = RawModelDetection(
        modelId: 'model_a_yolo',
        classId: 0,
        className: 'person',
        confidence: 0.88,
        box: Rect.fromLTWH(0.20, 0.15, 0.30, 0.60),
        timestamp: 1000,
      );

      const detB = RawModelDetection(
        modelId: 'model_b_feature',
        classId: 0,
        className: 'person',
        confidence: 0.82,
        box: Rect.fromLTWH(0.22, 0.16, 0.29, 0.58),
        timestamp: 1000,
      );

      const activeModels = [
        ModelMetadata(id: 'model_a_yolo', name: 'Model A', description: '', version: '', weight: 1.0),
        ModelMetadata(id: 'model_b_feature', name: 'Model B', description: '', version: '', weight: 0.9),
      ];

      final fused = engine.fuse(
        modelDetections: [
          [detA],
          [detB],
        ],
        activeModels: activeModels,
        timestamp: 1000,
      );

      expect(fused.length, 1);
      final unified = fused.first;
      expect(unified.className, 'person');
      expect(unified.agreementCount, 2);
      expect(unified.activeModelCount, 2);
      expect(unified.agreementRatio, 1.0);
      expect(unified.agreementBadge, '2/2');
      expect(unified.confidence, greaterThan(0.85));
    });
  });

  group('MultiObjectTracker Level 2', () {
    test('transitions track through tentative -> active -> lost -> removed lifecycle', () {
      final tracker = MultiObjectTracker(
        confirmationFrames: 2,
        maxMissedFrames: 2,
        iouMatchThreshold: 0.30,
      );

      // Frame 1: Tentative candidate
      const det1 = UnifiedDetection(
        className: 'person',
        box: Rect.fromLTWH(0.2, 0.2, 0.3, 0.5),
        confidence: 0.85,
        contributingModelIds: ['model_a_yolo', 'model_b_feature'],
        agreementCount: 2,
        activeModelCount: 2,
        timestamp: 1000,
        colorHex: 0xFF00E5A0,
      );

      final tracksFrame1 = tracker.update([det1], timestamp: 1000);
      expect(tracksFrame1, isEmpty); // Not confirmed yet (confirmationFrames = 2)
      expect(tracker.allTracks.length, 1);
      expect(tracker.allTracks.first.state, TrackState.tentative);

      // Frame 2: Confirmed active track
      const det2 = UnifiedDetection(
        className: 'person',
        box: Rect.fromLTWH(0.21, 0.20, 0.3, 0.5),
        confidence: 0.89,
        contributingModelIds: ['model_a_yolo', 'model_b_feature'],
        agreementCount: 2,
        activeModelCount: 2,
        timestamp: 1033,
        colorHex: 0xFF00E5A0,
      );

      final tracksFrame2 = tracker.update([det2], timestamp: 1033);
      expect(tracksFrame2.length, 1);
      expect(tracksFrame2.first.state, TrackState.active);
      expect(tracksFrame2.first.trackId, 1);

      // Frame 3: Missed frame -> Lost state
      tracker.update([], timestamp: 1066);
      expect(tracker.allTracks.first.state, TrackState.lost);
      expect(tracker.allTracks.first.missedFrames, 1);

      // Frame 4 & 5: Continued missed -> Removed
      tracker.update([], timestamp: 1100);
      tracker.update([], timestamp: 1133);
      expect(tracker.allTracks, isEmpty); // Cleanly pruned from memory
    });
  });
}
