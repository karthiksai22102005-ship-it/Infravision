/// CANDIDATE SEARCH SERVICE — efficient spatial & status pre-filtering.
/// Avoids O(N) comparisons over large datasets by filtering to candidate issues
/// within an indexed spatial bounding box and active lifecycle states.
library;

import 'dart:math' as math;

import '../models/observation.dart';
import '../models/physical_issue.dart';

class CandidateSearchService {
  const CandidateSearchService();

  /// Filters [allIssues] to relevant candidate issues for [obs].
  /// If [obs] has no valid GPS (0.0, 0.0 or missing), returns all open issues.
  List<PhysicalIssue> findCandidates(
    Observation obs,
    List<PhysicalIssue> allIssues, {
    double searchRadiusMeters = 500.0,
    bool includeClosed = false,
  }) {
    final openIssues = includeClosed
        ? allIssues
        : allIssues.where((i) => i.status.isOpen).toList();

    // If observation has no coordinates, fallback to open candidates without spatial cull
    if (obs.latitude == 0.0 && obs.longitude == 0.0) {
      return openIssues;
    }

    final candidates = <PhysicalIssue>[];
    for (final issue in openIssues) {
      if (issue.primaryLat == 0.0 && issue.primaryLng == 0.0) {
        candidates.add(issue);
        continue;
      }

      final dist = haversineDistance(
        obs.latitude,
        obs.longitude,
        issue.primaryLat,
        issue.primaryLng,
      );

      // Check if within the broad candidate search radius
      if (dist <= searchRadiusMeters) {
        candidates.add(issue);
      }
    }

    return candidates;
  }

  /// Calculates geodesic distance between two points in meters using Haversine formula.
  static double haversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusM = 6371000.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusM * c;
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180.0;
}
