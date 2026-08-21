import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:infravision_camera/infravision_camera.dart';
import 'lightweight_object_detector.dart';

enum QualityGrade {
  good,
  acceptable,
  lowQuality,
  insufficient,
}

class ImageQualityResult {
  const ImageQualityResult({
    required this.grade,
    required this.sharpnessScore,
    required this.brightness,
    required this.contrast,
    required this.message,
  });

  final QualityGrade grade;
  final double sharpnessScore;
  final double brightness;
  final double contrast;
  final String message;
}

class ImageAnalysisResult {
  const ImageAnalysisResult({
    required this.imageFile,
    required this.imageWidth,
    required this.imageHeight,
    required this.quality,
    required this.detections,
    required this.latencyMs,
  });

  final File imageFile;
  final int imageWidth;
  final int imageHeight;
  final ImageQualityResult quality;
  final List<VisionDetection> detections;
  final double latencyMs;
}

/// Service that analyzes static image files for infrastructure defects.
class ImageAnalysisService {
  ImageAnalysisService._();
  static final ImageAnalysisService instance = ImageAnalysisService._();

  final LightweightObjectDetector _detector = LightweightObjectDetector();

  Future<ImageAnalysisResult?> analyzeImage(File file, {double minConfidence = 0.40}) async {
    final sw = Stopwatch()..start();
    final bytes = await file.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    final width = decoded.width;
    final height = decoded.height;

    // Convert decoded image to RGBA32 byte buffer
    final rgba = decoded.convert(numChannels: 4);
    final rawBytes = rgba.getBytes();

    // 1. Image Quality Assessment
    final quality = _assessQuality(rawBytes, width, height);

    // 2. Inference (if quality is sufficient)
    List<VisionDetection> detections = [];
    if (quality.grade != QualityGrade.insufficient) {
      final frame = CameraFrame(
        bytes: rawBytes,
        width: width,
        height: height,
        pixelFormat: 'RGBA32',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      detections = _detector.detect(frame, minConfidence: minConfidence);
    }

    sw.stop();
    return ImageAnalysisResult(
      imageFile: file,
      imageWidth: width,
      imageHeight: height,
      quality: quality,
      detections: detections,
      latencyMs: sw.elapsedMicroseconds / 1000.0,
    );
  }

  ImageQualityResult _assessQuality(Uint8List bytes, int width, int height) {
    if (width < 32 || height < 32 || bytes.isEmpty) {
      return const ImageQualityResult(
        grade: QualityGrade.insufficient,
        sharpnessScore: 0,
        brightness: 0,
        contrast: 0,
        message: 'Insufficient resolution for reliable visual analysis.',
      );
    }

    // Sample pixels to compute mean luma, contrast, and gradient sharpness
    const sampleW = 64;
    const sampleH = 48;
    final luma = Float32List(sampleW * sampleH);
    double sumLuma = 0.0;

    for (var gy = 0; gy < sampleH; gy++) {
      final y = ((gy + 0.5) * height / sampleH).floor().clamp(0, height - 1);
      final rowOffset = y * width * 4;

      for (var gx = 0; gx < sampleW; gx++) {
        final x = ((gx + 0.5) * width / sampleW).floor().clamp(0, width - 1);
        final idx = rowOffset + x * 4;

        final r = bytes[idx];
        final g = bytes[idx + 1];
        final b = bytes[idx + 2];

        final val = 0.299 * r + 0.587 * g + 0.114 * b;
        luma[gy * sampleW + gx] = val;
        sumLuma += val;
      }
    }

    final meanLuma = sumLuma / (sampleW * sampleH);

    // Variance (Contrast)
    double sumVar = 0.0;
    for (final v in luma) {
      final diff = v - meanLuma;
      sumVar += diff * diff;
    }
    final contrast = math.sqrt(sumVar / (sampleW * sampleH));

    // Sobel gradient energy (Sharpness)
    double sumGrad = 0.0;
    var gradCount = 0;
    for (var y = 1; y < sampleH - 1; y++) {
      final yPrev = (y - 1) * sampleW;
      final yNext = (y + 1) * sampleW;
      final yCur = y * sampleW;

      for (var x = 1; x < sampleW - 1; x++) {
        final dx = (luma[yPrev + x + 1] + 2 * luma[yCur + x + 1] + luma[yNext + x + 1]) -
            (luma[yPrev + x - 1] + 2 * luma[yCur + x - 1] + luma[yNext + x - 1]);
        final dy = (luma[yNext + x - 1] + 2 * luma[yNext + x] + luma[yNext + x + 1]) -
            (luma[yPrev + x - 1] + 2 * luma[yPrev + x] + luma[yPrev + x + 1]);

        sumGrad += math.sqrt(dx * dx + dy * dy);
        gradCount++;
      }
    }
    final sharpness = gradCount > 0 ? (sumGrad / gradCount) : 0.0;

    // Quality Categorization
    if (meanLuma < 25) {
      return ImageQualityResult(
        grade: QualityGrade.insufficient,
        sharpnessScore: sharpness,
        brightness: meanLuma,
        contrast: contrast,
        message: 'Image is too dark (underexposed). Human verification required.',
      );
    } else if (meanLuma > 240) {
      return ImageQualityResult(
        grade: QualityGrade.insufficient,
        sharpnessScore: sharpness,
        brightness: meanLuma,
        contrast: contrast,
        message: 'Image is washed out (overexposed). Human verification required.',
      );
    } else if (sharpness < 12.0) {
      return ImageQualityResult(
        grade: QualityGrade.lowQuality,
        sharpnessScore: sharpness,
        brightness: meanLuma,
        contrast: contrast,
        message: 'Low sharpness or motion blur detected. Results may be tentative.',
      );
    } else if (contrast < 20.0) {
      return ImageQualityResult(
        grade: QualityGrade.acceptable,
        sharpnessScore: sharpness,
        brightness: meanLuma,
        contrast: contrast,
        message: 'Acceptable image quality with low visual contrast.',
      );
    }

    return ImageQualityResult(
      grade: QualityGrade.good,
      sharpnessScore: sharpness,
      brightness: meanLuma,
      contrast: contrast,
      message: 'Optimal illumination and edge sharpness for AI inspection.',
    );
  }
}
