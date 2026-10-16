import 'package:citizen_app/core/vision/defect_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('YOLOv8 output decoding', () {
    test('decodes channel-major output and suppresses same-class overlaps', () {
      // [1, 4 + 3 classes, 3 anchors], boxes are model-input pixels.
      final output = <double>[
        160, 162, 40, // cx
        160, 160, 40, // cy
        80, 82, 30, // width
        80, 82, 30, // height
        .90, .80, .10, // crocodile crack
        .05, .10, .82, // longitudinal crack
        .03, .04, .02, // pothole
      ];

      final detections = CitizenDefectDetector.decodeYoloV8(
        values: output,
        shape: const [1, 7, 3],
        labels: const ['crocodile crack', 'longitudinal crack', 'pothole'],
        inputSize: 320,
      );

      expect(detections, hasLength(2));
      expect(detections.first.label, 'crocodile crack');
      expect(detections.first.confidence, closeTo(.90, .001));
      expect(detections.first.left, closeTo(.375, .001));
      expect(detections.last.label, 'longitudinal crack');
    });

    test('decodes row-major normalized output and ignores low confidence', () {
      final detections = CitizenDefectDetector.decodeYoloV8(
        values: const [
          .50, .50, .25, .25, .01, .02, .97,
          .20, .20, .10, .10, .05, .10, .20,
        ],
        shape: const [1, 2, 7],
        labels: const ['crocodile crack', 'longitudinal crack', 'pothole'],
        inputSize: 320,
      );

      expect(detections, hasLength(1));
      expect(detections.single.label, 'pothole');
      expect(detections.single.left, closeTo(.375, .001));
      expect(detections.single.bottom, closeTo(.625, .001));
    });

    test('decodes real model single-class pothole tensor [1, 5, 8400]', () {
      // Simulate real Kaggle/Roboflow pothole model output:
      // shape: [1, 5, 8400] where 5 = [cx, cy, w, h, pothole_score]
      const anchors = 8400;
      final values = List<double>.filled(5 * anchors, 0.0);

      // Place a high-confidence pothole at anchor 42
      const targetAnchor = 42;
      values[0 * anchors + targetAnchor] = 320.0; // cx
      values[1 * anchors + targetAnchor] = 320.0; // cy
      values[2 * anchors + targetAnchor] = 160.0; // w
      values[3 * anchors + targetAnchor] = 160.0; // h
      values[4 * anchors + targetAnchor] = 0.88;  // pothole confidence

      final detections = CitizenDefectDetector.decodeYoloV8(
        values: values,
        shape: const [1, 5, anchors],
        labels: CitizenDefectDetector.labels, // ['pothole']
        inputSize: 640,
        confidenceThreshold: 0.35,
      );

      expect(detections, hasLength(1));
      expect(detections.first.label, 'pothole');
      expect(detections.first.classId, 0);
      expect(detections.first.confidence, closeTo(0.88, 0.001));
      // cx = 320 / 640 = 0.5, w = 160 / 640 = 0.25 -> left = 0.5 - 0.125 = 0.375
      expect(detections.first.left, closeTo(0.375, 0.001));
      expect(detections.first.right, closeTo(0.625, 0.001));
    });
  });
}
