import '../models/complaint.dart';

/// Simulated central backend / database.
///
/// In this fully-offline-first prototype there is no live server, so this
/// remote data source models the real-time authority workflow: when the app
/// is "online" it accepts complaint uploads, assigns an official Case ID, and
/// holds a canonical copy representing what other inspectors/crews see. When
/// offline it simply records that items are pending. Swap this with the real
/// backend + WebSocket layer without touching the rest of the architecture.
class RemoteComplaintDataSource {
  RemoteComplaintDataSource();

  bool _online = true;
  final Map<String, Complaint> _canonical = {};
  int _caseCounter = 1000;

  bool get isOnline => _online;
  set online(bool value) => _online = value;

  bool hasRemote(String id) => _canonical.containsKey(id);

  /// Uploads a draft complaint and returns the official Case ID.
  String? upload(Complaint draft) {
    if (!_online) return null;
    final caseId =
        'IV-${DateTime.now().year}-${(_caseCounter++).toString().padLeft(4, '0')}';
    draft.caseId = caseId;
    _canonical[draft.id] = draft;
    return caseId;
  }

  /// Applies a status / timeline update to the canonical copy.
  void update(Complaint updated) {
    if (!_online) return;
    _canonical[updated.id] = updated;
  }

  /// Simulated "other citizens confirm same issue" activity for the community.
  void applyConfirmation(String id, int total) {
    final c = _canonical[id];
    if (c == null) return;
    c.confirmationCount = total;
  }

  Complaint? pull(String id) => _canonical[id];
}
