import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infravision/models/detection_history_entry.dart';
import 'package:infravision/tracking/object_tracker.dart';
import 'package:infravision/vision/lightweight_object_detector.dart';
import 'package:infravision/vision/local_model_runner.dart';
import 'package:infravision_camera/infravision_camera.dart';

void main() {
  group('LightweightObjectDetector', () {
    test('detect returns empty list for empty/invalid frame', () {
      final detector = LightweightObjectDetector();
      final emptyFrame = CameraFrame(
        bytes: Uint8List(0),
        width: 0,
        height: 0,
        timestamp: 0,
        pixelFormat: 'RGBA32',
      );
      final detections = detector.detect(emptyFrame);
      expect(detections, isEmpty);
    });

    test('detect handles valid RGBA32 buffer without throwing', () {
      final detector = LightweightObjectDetector();
      const width = 64;
      const height = 48;
      final bytes = Uint8List(width * height * 4);

      // Draw a synthetic bright square in the center
      for (var y = 15; y < 35; y++) {
        for (var x = 20; x < 45; x++) {
          final idx = (y * width + x) * 4;
          bytes[idx] = 255;     // R
          bytes[idx + 1] = 255; // G
          bytes[idx + 2] = 255; // B
          bytes[idx + 3] = 255; // A
        }
      }

      final frame = CameraFrame(
        bytes: bytes,
        width: width,
        height: height,
        timestamp: 1000,
        pixelFormat: 'RGBA32',
      );

      final detections = detector.detect(frame, minConfidence: 0.30);
      expect(detections, isA<List<VisionDetection>>());
    });
  });

  group('ObjectTracker', () {
    test('assigns persistent track IDs and smooths coordinates', () {
      final tracker = ObjectTracker();

      const det1 = [
        VisionDetection(
          box: Rect.fromLTWH(0.2, 0.2, 0.3, 0.4),
          label: 'person',
          confidence: 0.85,
          colorHex: 0xFF00E5A0,
          center: Offset(0.35, 0.4),
        ),
      ];

      final tracks1 = tracker.update(det1);
      expect(tracks1.length, 1);
      expect(tracks1.first.trackId, 1);
      expect(tracks1.first.label, 'person');

      // Second frame with slightly shifted box
      const det2 = [
        VisionDetection(
          box: Rect.fromLTWH(0.22, 0.21, 0.3, 0.4),
          label: 'person',
          confidence: 0.88,
          colorHex: 0xFF00E5A0,
          center: Offset(0.37, 0.41),
        ),
      ];

      final tracks2 = tracker.update(det2);
      expect(tracks2.length, 1);
      expect(tracks2.first.trackId, 1); // ID persists across frames
      expect(tracks2.first.framesTracked, 2);
    });
  });

  group('DetectionHistoryEntry', () {
    test('creates entry with correct properties and time formatting', () {
      final time = DateTime(2026, 8, 19, 15, 30, 45);
      final entry = DetectionHistoryEntry(
        className: 'person',
        confidence: 0.94,
        timestamp: time,
        count: 3,
      );

      expect(entry.className, 'person');
      expect(entry.confidence, 0.94);
      expect(entry.count, 3);
      expect(entry.formattedTime, '15:30:45');
    });
  });

  group('LocalModelRunner', () {
    test('runs fallback inference safely on valid frame', () {
      final runner = LocalModelRunner();
      const width = 32;
      const height = 24;
      final bytes = Uint8List(width * height * 4);

      final frame = CameraFrame(
        bytes: bytes,
        width: width,
        height: height,
        timestamp: 2000,
        pixelFormat: 'RGBA32',
      );

      final results = runner.runInference(frame, minConfidence: 0.5);
      expect(results, isA<List<VisionDetection>>());
    });
  });
}
