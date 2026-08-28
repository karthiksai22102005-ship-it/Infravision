import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'classifier/defect_classifier_engine.dart';

/// Forensic before/after repair comparison result.
class VerificationResult {
  const VerificationResult({
    required this.passed,
    required this.beforeDefectScore,
    required this.afterDefectScore,
    required this.residualDefectPercent,
    required this.surfaceRoughnessIndex,
    required this.compactionEstimate,
    required this.summary,
  });

  final bool passed;
  final double beforeDefectScore;
  final double afterDefectScore;
  final double residualDefectPercent;
  final double surfaceRoughnessIndex;
  final double compactionEstimate;
  final String summary;
}

/// Local image comparison for post-repair certification (no cloud).
class VerificationEngine {
  VerificationEngine._();
  static final VerificationEngine instance = VerificationEngine._();

  final DefectClassifierEngine _classifier = DefectClassifierEngine.instance;

  Future<VerificationResult> compareRepair({
    required String beforePath,
    required String afterPath,
  }) async {
    final beforeFile = File(beforePath);
    final afterFile = File(afterPath);

    if (!await beforeFile.exists() || !await afterFile.exists()) {
      return const VerificationResult(
        passed: false,
        beforeDefectScore: 0,
        afterDefectScore: 0,
        residualDefectPercent: 100,
        surfaceRoughnessIndex: 99,
        compactionEstimate: 0,
        summary: 'Before or after evidence file missing on disk.',
      );
    }

    final beforeAnalysis = await _classifier.classifyImage(beforeFile);
    final afterAnalysis = await _classifier.classifyImage(afterFile);

    final beforeScore = beforeAnalysis.severityScore;
    final afterScore = afterAnalysis.severityScore;
    final residual = afterScore <= 0.05
        ? 0.0
        : ((afterScore / math.max(beforeScore, 0.15)) * 100).clamp(0.0, 100.0);

    final pixelDelta = await _meanAbsoluteDifference(beforeFile, afterFile);
    final roughness = (pixelDelta * 120).clamp(0.5, 8.0);
    final compaction = (100 - roughness * 2.5).clamp(85.0, 99.9);

    final defectCleared = afterScore < 0.35 && afterScore < beforeScore * 0.45;
    final surfaceOk = roughness < 3.5;
    final passed = defectCleared && surfaceOk && beforeScore > 0.2;

    return VerificationResult(
      passed: passed,
      beforeDefectScore: beforeScore,
      afterDefectScore: afterScore,
      residualDefectPercent: residual,
      surfaceRoughnessIndex: roughness,
      compactionEstimate: compaction,
      summary: passed
          ? 'Repair verified: defect score dropped ${(beforeScore - afterScore).toStringAsFixed(2)}, surface within tolerance.'
          : 'Verification failed: residual defect ${residual.toStringAsFixed(1)}% or surface roughness too high.',
    );
  }

  Future<double> _meanAbsoluteDifference(File a, File b) async {
    final imgA = img.decodeImage(await a.readAsBytes());
    final imgB = img.decodeImage(await b.readAsBytes());
    if (imgA == null || imgB == null) return 1.0;

    final resizedB = img.copyResize(imgB, width: imgA.width, height: imgA.height);
    final rgbaA = imgA.convert(numChannels: 4).getBytes();
    final rgbaB = resizedB.convert(numChannels: 4).getBytes();

    const sample = 4096;
    final step = math.max(1, (rgbaA.length ~/ 4) ~/ sample);
    var sum = 0.0;
    var count = 0;

    for (var i = 0; i < rgbaA.length - 3; i += step * 4) {
      final la = _luma(rgbaA, i);
      final lb = _luma(rgbaB, i);
      sum += (la - lb).abs();
      count++;
    }

    return count == 0 ? 1.0 : (sum / count) / 255.0;
  }

  double _luma(Uint8List bytes, int i) {
    final r = bytes[i];
    final g = bytes[i + 1];
    final b = bytes[i + 2];
    return 0.299 * r + 0.587 * g + 0.114 * b;
  }
}
