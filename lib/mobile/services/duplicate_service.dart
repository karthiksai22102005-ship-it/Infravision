import 'dart:math' as math;

import '../config/mobile_config.dart';
import '../models/analysis.dart';
import '../models/observation.dart';

/// Advisory, on-device duplicate detection (§40).
///
/// Uses GPS proximity, category, recency and — when both sides have images —
/// perceptual hash similarity. The result is always advisory: the user decides,
/// and the server-side check remains authoritative.
class DuplicateService {
  DuplicateService._();

  static final DuplicateService instance = DuplicateService._();

  /// [hashesByObservation] maps observation id -> perceptual hashes of the
  /// images already stored for it (empty when a record has no images yet).
  DuplicateMatch? check({
    required List<Observation> candidates,
    required String categoryId,
    required LocationFix location,
    Map<String, List<String>> hashesByObservation = const <String, List<String>>{},
    List<String> newHashes = const <String>[],
    String? ignoreObservationId,
  }) {
    final DateTime now = DateTime.now();
    DuplicateMatch? best;

    for (final Observation candidate in candidates) {
      if (candidate.id == ignoreObservationId) continue;
      if (candidate.status == ObservationStatus.draft) continue;

      final double distance = haversineMeters(
        location.latitude,
        location.longitude,
        candidate.location.latitude,
        candidate.location.longitude,
      );
      if (distance > 100) continue;

      final Duration age = now.difference(candidate.createdAt);
      if (age > MobileConfig.duplicateWindow) continue;

      final bool sameCategory = candidate.category == categoryId;
      final List<String> reasons = <String>[];

      if (sameCategory && distance <= MobileConfig.duplicateRadiusMeters) {
        reasons.add('Same issue category');
        reasons.add('${distance.round()} m away');
        reasons.add(_ageLabel(age));
      }

      int? hashDistance;
      final List<String> existingHashes =
          hashesByObservation[candidate.id] ?? const <String>[];
      if (newHashes.isNotEmpty && existingHashes.isNotEmpty) {
        hashDistance = _bestHashDistance(newHashes, existingHashes);
      }

      final bool imageMatch = hashDistance != null &&
          hashDistance <= MobileConfig.duplicateHashDistance &&
          (sameCategory || distance <= MobileConfig.duplicateRadiusMeters);

      if (reasons.isEmpty && !imageMatch) continue;
      if (imageMatch) {
        reasons.add('Images look similar (dHash $hashDistance/64)');
        if (reasons.length == 1) {
          reasons.add('${distance.round()} m away');
          reasons.add(_ageLabel(age));
        }
      }

      final DuplicateMatch match = DuplicateMatch(
        observationId: candidate.id,
        category: candidate.category,
        distanceMeters: distance,
        createdAt: candidate.createdAt,
        reasons: reasons,
        hashDistance: hashDistance,
      );
      if (best == null || match.distanceMeters < best.distanceMeters) {
        best = match;
      }
    }
    return best;
  }

  String _ageLabel(Duration age) {
    if (age.inMinutes < 60) return '${age.inMinutes} min ago';
    if (age.inHours < 24) return '${age.inHours} h ago';
    return '${age.inDays} d ago';
  }

  /// Smallest Hamming distance between any pair of the two hash sets.
  int? _bestHashDistance(List<String> a, List<String> b) {
    if (a.isEmpty || b.isEmpty) return null;
    int best = 64;
    for (final String left in a) {
      for (final String right in b) {
        final int distance = hammingDistance(left, right);
        if (distance < best) best = distance;
      }
    }
    return best;
  }

  /// Hamming distance between two hex perceptual hashes (16 hex chars = 64 bit).
  static int hammingDistance(String a, String b) {
    if (a.length != b.length) return 64;
    int distance = 0;
    for (int i = 0; i < a.length; i++) {
      final int va = int.tryParse(a[i], radix: 16) ?? 0;
      final int vb = int.tryParse(b[i], radix: 16) ?? 0;
      int xor = va ^ vb;
      while (xor != 0) {
        distance += xor & 1;
        xor >>= 1;
      }
    }
    return distance;
  }

  /// Great-circle distance in metres (Haversine, `dart:math`).
  static double haversineMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371000.0;
    final double dLat = _rad(lat2 - lat1);
    final double dLon = _rad(lon2 - lon1);
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double degrees) => degrees * math.pi / 180.0;
}