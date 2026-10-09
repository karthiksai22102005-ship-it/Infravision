/// OBSERVATION ADAPTERS — zero-copy bridges from every existing portal model
/// into the domain-independent [Observation] entity. Existing models are
/// never modified; they are merely *viewed* as observations.
library;

import '../citizen/models/complaint.dart';
import 'models/observation.dart';

class ObservationAdapters {
  ObservationAdapters._();

  static String _issueTypeOf(Complaint c) =>
      c.aiDiagnosis ?? c.category;

  /// Citizen quick-report / confirmation / evidence events.
  static Observation fromComplaint(Complaint c,
      {ObservationSourceType sourceType = ObservationSourceType.citizenReport}) {
    return Observation(
      observationId: 'OBS-${c.id}-${DateTime.now().millisecondsSinceEpoch}',
      sourceType: sourceType,
      sourceId: c.id,
      timestamp: c.updatedAt ?? c.createdAt,
      latitude: c.latitude,
      longitude: c.longitude,
      locationAccuracy: 12,
      media: [...c.images, ...c.videos],
      detectedIssueType: _issueTypeOf(c),
      classification: c.category,
      aiConfidence: c.aiConfidence,
      userDescription: c.description,
      contextData: {'address': c.address, 'priorityScore': c.priorityScore},
      deviceInformation: 'citizen-app',
    );
  }

  /// Authority-portal twin (field agent / AI batch detections mirrored from
  /// inspector logs). The citizen twin carries the same physical location.
  static Observation fromAgentMirror(Complaint c) {
    final obs = fromComplaint(c, sourceType: ObservationSourceType.fieldAgent);
    return Observation(
      observationId: obs.observationId.replaceFirst('OBS-', 'OBS-FA-'),
      sourceType: ObservationSourceType.fieldAgent,
      sourceId: obs.sourceId,
      timestamp: obs.timestamp,
      latitude: obs.latitude,
      longitude: obs.longitude,
      locationAccuracy: obs.locationAccuracy,
      media: obs.media,
      detectedIssueType: obs.detectedIssueType,
      classification: obs.classification,
      aiConfidence: obs.aiConfidence,
      userDescription: obs.userDescription,
      contextData: obs.contextData,
      deviceInformation: 'field-agent-portal',
    );
  }

  /// Crew resolution evidence — used by the verification stage.
  static Observation fromResolutionEvidence(Complaint c, String evidencePath) {
    final base = fromComplaint(c,
        sourceType: ObservationSourceType.resolutionEvidence);
    return Observation(
      observationId:
          'OBS-RES-${DateTime.now().millisecondsSinceEpoch}',
      sourceType: ObservationSourceType.resolutionEvidence,
      sourceId: base.sourceId,
      timestamp: DateTime.now(),
      latitude: base.latitude,
      longitude: base.longitude,
      locationAccuracy: base.locationAccuracy,
      media: [if (evidencePath.isNotEmpty) evidencePath],
      detectedIssueType: base.detectedIssueType,
      classification: base.classification,
      userDescription: 'Resolution evidence uploaded by resolution team',
      contextData: base.contextData,
      deviceInformation: 'crew-portal',
    );
  }
}
