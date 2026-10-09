import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../config/mobile_config.dart';
import '../core/app_logger.dart';
import '../core/result.dart';
import '../models/analysis.dart';

/// Everything derived from one capture in a single background pass (§13/§14).
class ProcessedEvidence {
  const ProcessedEvidence({
    required this.originalPath,
    required this.uploadPath,
    required this.aiPath,
    required this.thumbnailPath,
    required this.sha256,
    required this.perceptualHash,
    required this.width,
    required this.height,
    required this.originalBytes,
    required this.uploadBytes,
    required this.thumbnailBytes,
    required this.quality,
  });

  final String originalPath;
  final String uploadPath;
  final String aiPath;
  final String thumbnailPath;
  final String sha256;
  final String perceptualHash;
  final int width;
  final int height;
  final int originalBytes;
  final int uploadBytes;
  final int thumbnailBytes;
  final QualityReport quality;
}

/// Metadata measured for a video evidence clip (§16).
class VideoEvidenceMeta {
  const VideoEvidenceMeta({
    required this.sha256,
    required this.sizeBytes,
    required this.durationMs,
  });

  final String sha256;
  final int sizeBytes;
  final int durationMs;
}

/// Disk-backed capture pipeline.
///
/// Guarantees:
/// - the original file is NEVER re-encoded or overwritten;
/// - decoding/resizing/compressing happens in an isolate so the UI thread
///   stays responsive (§56);
/// - only the sizes the current performance profile needs are produced (§51-54);
/// - video is never loaded into memory — only streamed for hashing (§16).
class ImagePipelineService {
  ImagePipelineService._();

  static final ImagePipelineService instance = ImagePipelineService._();

  /// Validates a picked/recorded file *before* importing it (§17).
  /// Never trusts the extension alone: the magic bytes must match too.
  Future<Failure?> validateFile(File file) async {
    try {
      if (!await file.exists()) {
        return const Failure('missing_file', 'The selected file could not be found.');
      }
      final int size = await file.length();
      if (size <= 0) {
        return const Failure('empty_file', 'The selected file is empty.');
      }
      final String extension = file.path.split('.').last.toLowerCase();
      final bool isImage = MobileConfig.allowedImageExtensions.contains(extension);
      final bool isVideo = MobileConfig.allowedVideoExtensions.contains(extension);
      if (!isImage && !isVideo) {
        return Failure(
          'unsupported_type',
          'Unsupported file type .$extension.',
        );
      }
      if (isImage && size > MobileConfig.maxPhotoBytes) {
        return const Failure(
          'file_too_large',
          'Photo is larger than ${MobileConfig.maxPhotoBytes ~/ (1024 * 1024)} MB.',
        );
      }
      if (isVideo && size > MobileConfig.maxVideoBytes) {
        return const Failure(
          'file_too_large',
          'Video is larger than ${MobileConfig.maxVideoBytes ~/ (1024 * 1024)} MB.',
        );
      }

      // Magic-byte sniff: JPEG/PNG/WEBP vs MP4/MOV/3GP/MKV.
      final RandomAccessFile handle = await file.open();
      final Uint8List header = await handle.read(16);
      await handle.close();
      final bool looksValid = _matchesMagic(header, isImage: isImage);
      if (!looksValid) {
        return const Failure(
          'content_mismatch',
          'The file contents do not match its extension.',
        );
      }
      return null;
    } catch (e) {
      AppLog.e('Pipeline', 'Validation failed: $e');
      return const Failure('validation_failed', 'The file could not be verified.');
    }
  }

  bool _matchesMagic(Uint8List header, {required bool isImage}) {
    if (header.length < 4) return false;
    final bool jpeg = header[0] == 0xFF && header[1] == 0xD8 && header[2] == 0xFF;
    final bool png = header[0] == 0x89 && header[1] == 0x50 && header[2] == 0x4E;
    final bool webp = header[0] == 0x52 && header[1] == 0x49;
    final bool ftyp = header.length >= 8 &&
        header[4] == 0x66 &&
        header[5] == 0x74 &&
        header[6] == 0x79 &&
        header[7] == 0x70;
    final bool riff = header[0] == 0x52 && header[1] == 0x49 && header[2] == 0x46;
    final bool matroska = header[0] == 0x1A && header[1] == 0x45;
    return isImage ? (jpeg || png || webp) : (ftyp || riff || matroska);
  }
  /// Runs the whole still-image pipeline in a background isolate.
  Future<Result<ProcessedEvidence>> processImage({
    required String sourcePath,
    required String uploadPath,
    required String aiPath,
    required String thumbnailPath,
    int uploadMaxDimension = MobileConfig.uploadDerivativeMaxDimension,
    int aiMaxDimension = MobileConfig.aiDerivativeMaxDimension,
    int thumbnailMaxDimension = MobileConfig.thumbnailMaxDimension,
    int jpegQuality = 85,
  }) async {
    try {
      final Map<String, Object?> response = await compute(
        processImageJob,
        <String, Object?>{
          'sourcePath': sourcePath,
          'uploadPath': uploadPath,
          'aiPath': aiPath,
          'thumbnailPath': thumbnailPath,
          'uploadMax': uploadMaxDimension,
          'aiMax': aiMaxDimension,
          'thumbMax': thumbnailMaxDimension,
          'quality': jpegQuality,
        },
      );

      if (response['ok'] != true) {
        return Err<ProcessedEvidence>(
          Failure(
            'processing_failed',
            '${response['error'] ?? 'The image could not be processed.'}',
          ),
        );
      }

      final Map<String, Object?> screening =
          Map<String, Object?>.from(response['screening']! as Map);
      final Map<String, Object?> quality =
          Map<String, Object?>.from(response['quality']! as Map);
      final List<Object?> findings = quality['findings']! as List<Object?>;

      final QualityReport report = QualityReport(
        grade: switch ('${quality['grade']}') {
          'excellent' => QualityGrade.excellent,
          'acceptable' => QualityGrade.acceptable,
          'poor' => QualityGrade.poor,
          _ => QualityGrade.unavailable,
        },
        findings: findings
            .map((Object? f) => QualityFinding(
                  '${(f! as Map)['code']}',
                  '${(f as Map)['message']}',
                ))
            .toList(growable: false),
        screening: VisualScreening(
          meanLuminance: (screening['luminance']! as num).toDouble(),
          luminanceStdDev: (screening['contrast']! as num).toDouble(),
          laplacianVariance: (screening['blur']! as num).toDouble(),
          edgeDensity: (screening['edges']! as num).toDouble(),
          darkRegionRatio: (screening['dark']! as num).toDouble(),
          sampledWidth: (screening['sampleW']! as num).toInt(),
          sampledHeight: (screening['sampleH']! as num).toInt(),
        ),
        width: (response['width']! as num).toInt(),
        height: (response['height']! as num).toInt(),
      );

      return Ok<ProcessedEvidence>(
        ProcessedEvidence(
          originalPath: sourcePath,
          uploadPath: uploadPath,
          aiPath: aiPath,
          thumbnailPath: thumbnailPath,
          sha256: '${response['sha256']}',
          perceptualHash: '${response['phash']}',
          width: (response['width']! as num).toInt(),
          height: (response['height']! as num).toInt(),
          originalBytes: (response['originalBytes']! as num).toInt(),
          uploadBytes: (response['uploadBytes']! as num).toInt(),
          thumbnailBytes: (response['thumbBytes']! as num).toInt(),
          quality: report,
        ),
      );
    } catch (e) {
      AppLog.e('Pipeline', 'Image pipeline failed: $e');
      return const Err<ProcessedEvidence>(
        Failure('processing_failed', 'The image could not be processed.'),
      );
    }
  }

  /// Videos are streamed only — never decoded into memory (§16).
  Future<Result<VideoEvidenceMeta>> processVideo({
    required String sourcePath,
    required Duration measuredDuration,
  }) async {
    try {
      final File file = File(sourcePath);
      if (!await file.exists()) {
        return const Err<VideoEvidenceMeta>(
          Failure('missing_file', 'The recorded video could not be found.'),
        );
      }
      final int size = await file.length();
      if (size > MobileConfig.maxVideoBytes) {
        return const Err<VideoEvidenceMeta>(
          Failure(
            'file_too_large',
            'Video is larger than ${MobileConfig.maxVideoBytes ~/ (1024 * 1024)} MB.',
          ),
        );
      }
      if (measuredDuration.inSeconds > MobileConfig.maxVideoDurationSeconds) {
        return const Err<VideoEvidenceMeta>(
          Failure(
            'too_long',
            'Video is longer than ${MobileConfig.maxVideoDurationSeconds} seconds.',
          ),
        );
      }
      final Digest digest = await sha256.bind(file.openRead()).first;
      return Ok<VideoEvidenceMeta>(
        VideoEvidenceMeta(
          sha256: digest.toString(),
          sizeBytes: size,
          durationMs: measuredDuration.inMilliseconds,
        ),
      );
    } catch (e) {
      AppLog.e('Pipeline', 'Video pipeline failed: $e');
      return const Err<VideoEvidenceMeta>(
        Failure('processing_failed', 'The video could not be processed.'),
      );
    }
  }
}

/// Isolate entry point: decodes, orients, measures, compresses and hashes one
/// still image. Runs entirely off the UI thread (§56).
@pragma('vm:entry-point')
Map<String, Object?> processImageJob(Map<String, Object?> request) {
  try {
    final String sourcePath = '${request['sourcePath']}';
    final Uint8List bytes = File(sourcePath).readAsBytesSync();
    final img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return <String, Object?>{
        'ok': false,
        'error': 'The image could not be decoded.',
      };
    }

    img.Image base = decoded;
    try {
      base = img.bakeOrientation(decoded);
    } catch (_) {
      base = decoded;
    }

    final int width = base.width;
    final int height = base.height;
    final int quality = (request['quality'] as num?)?.toInt() ?? 85;

    // --- Measured screening (§18) on a small sample, never the full image ---
    final int sampleW = width < 200 ? width : 160;
    final img.Image sample = img.copyResize(base, width: sampleW);
    final int sw = sample.width;
    final int sh = sample.height;
    final Float32List luma = Float32List(sw * sh);
    double sum = 0;
    double sumSq = 0;
    int dark = 0;
    for (int y = 0; y < sh; y++) {
      for (int x = 0; x < sw; x++) {
        final img.Pixel p = sample.getPixel(x, y);
        final double l = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
        luma[y * sw + x] = l;
        sum += l;
        sumSq += l * l;
        if (l < 48) dark++;
      }
    }
    final int pixels = sw * sh;
    final double mean = sum / pixels;
    final double variance = (sumSq / pixels) - (mean * mean);

    double lapSum = 0;
    double lapSq = 0;
    int lapCount = 0;
    int edges = 0;
    for (int y = 1; y < sh - 1; y++) {
      for (int x = 1; x < sw - 1; x++) {
        final int i = y * sw + x;
        final double lap =
            (luma[i - sw] + luma[i + sw] + luma[i - 1] + luma[i + 1] - 4 * luma[i]).abs();
        lapSum += lap;
        lapSq += lap * lap;
        lapCount++;
        if (lap > 60) edges++;
      }
    }
    final double lapMean = lapCount == 0 ? 0 : lapSum / lapCount;
    final double lapVariance =
        lapCount == 0 ? 0 : (lapSq / lapCount) - (lapMean * lapMean);

    // --- Derivatives: the original is never rewritten (§13/§14) ---
    final String uploadPath = '${request['uploadPath']}';
    final String aiPath = '${request['aiPath']}';
    final String thumbPath = '${request['thumbnailPath']}';
    final int uploadMax = (request['uploadMax'] as num?)?.toInt() ?? 1920;
    final int aiMax = (request['aiMax'] as num?)?.toInt() ?? 640;
    final int thumbMax = (request['thumbMax'] as num?)?.toInt() ?? 320;

    final File uploadFile = File(uploadPath);
    uploadFile.writeAsBytesSync(
      img.encodeJpg(_resizeMax(base, uploadMax), quality: quality),
    );
    final File aiFile = File(aiPath);
    aiFile.writeAsBytesSync(img.encodeJpg(_resizeMax(base, aiMax), quality: 85));
    final File thumbFile = File(thumbPath);
    thumbFile.writeAsBytesSync(
      img.encodeJpg(_resizeMax(base, thumbMax), quality: 72),
    );

    final String phash = _dHash(_resizeMax(base, 64));
    final String sha = sha256.convert(bytes).toString();

    // --- Quality gate (§18): only measurable, never fabricated ---
    final List<Map<String, Object?>> findings = <Map<String, Object?>>[];
    String grade = 'excellent';
    if (width < MobileConfig.minImageWidth || height < MobileConfig.minImageHeight) {
      grade = 'poor';
      findings.add(<String, Object?>{
        'code': 'low_resolution',
        'message':
            'Image is too small ($width×$height). Move closer to the defect.',
      });
    }
    if (mean < MobileConfig.minBrightness) {
      grade = 'poor';
      findings.add(<String, Object?>{
        'code': 'too_dark',
        'message': 'Image is too dark. Use flash or improve the lighting.',
      });
    } else if (mean > MobileConfig.maxBrightness) {
      grade = 'poor';
      findings.add(<String, Object?>{
        'code': 'too_bright',
        'message': 'Image is overexposed. Reduce glare or change the angle.',
      });
    }
    if (lapVariance < MobileConfig.minBlurVariance) {
      grade = 'poor';
      findings.add(<String, Object?>{
        'code': 'blurry',
        'message': 'Image is too blurry. Hold steady and tap to focus.',
      });
    }

    final double darkRatio = dark / pixels;
    final double edgeRatio = lapCount == 0 ? 0 : edges / lapCount;
    final double anomaly = ((darkRatio * 1.6).clamp(0.0, 1.0) * 0.55) +
        ((edgeRatio * 2.2).clamp(0.0, 1.0) * 0.25) +
        ((lapVariance / 400.0).clamp(0.0, 1.0) * 0.20);
    if (anomaly < 0.18) {
      findings.add(<String, Object?>{
        'code': 'framing',
        'message': 'Little surface detail is visible — move closer to the defect.',
      });
    }
    if (grade != 'poor') {
      grade = lapVariance > 120 ? 'excellent' : 'acceptable';
    }

    return <String, Object?>{
      'ok': true,
      'width': width,
      'height': height,
      'originalBytes': bytes.length,
      'uploadBytes': uploadFile.lengthSync(),
      'aiBytes': aiFile.lengthSync(),
      'thumbBytes': thumbFile.lengthSync(),
      'sha256': sha,
      'phash': phash,
      'screening': <String, Object?>{
        'luminance': mean,
        'contrast': variance.clamp(0.0, 65025.0),
        'blur': lapVariance.clamp(0.0, 100000.0),
        'edges': edgeRatio,
        'dark': darkRatio,
        'sampleW': sw,
        'sampleH': sh,
      },
      'quality': <String, Object?>{
        'grade': grade,
        'findings': findings,
      },
    };
  } catch (e) {
    return <String, Object?>{
      'ok': false,
      'error': 'The image could not be processed.',
      'detail': '$e',
    };
  }
}

img.Image _resizeMax(img.Image source, int maxDimension) {
  if (source.width <= maxDimension && source.height <= maxDimension) {
    return source;
  }
  return source.width >= source.height
      ? img.copyResize(source, width: maxDimension)
      : img.copyResize(source, height: maxDimension);
}

/// 64-bit difference hash — robust enough for advisory duplicate detection.
String _dHash(img.Image source) {
  final img.Image g = img.copyResize(source, width: 9, height: 8);
  final List<bool> bits = <bool>[];
  for (int y = 0; y < 8; y++) {
    for (int x = 0; x < 8; x++) {
      final img.Pixel left = g.getPixel(x, y);
      final img.Pixel right = g.getPixel(x + 1, y);
      final double l = 0.299 * left.r + 0.587 * left.g + 0.114 * left.b;
      final double r = 0.299 * right.r + 0.587 * right.g + 0.114 * right.b;
      bits.add(l > r);
    }
  }
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < 64; i += 4) {
    int nibble = 0;
    for (int b = 0; b < 4; b++) {
      nibble = (nibble << 1) | (bits[i + b] ? 1 : 0);
    }
    buffer.write(nibble.toRadixString(16));
  }
  return buffer.toString();
}