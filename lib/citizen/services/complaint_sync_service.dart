import 'package:flutter/foundation.dart';

import '../engines/complaint_sync_engine.dart';
import '../models/complaint.dart';
import 'complaint_event_service.dart';
import '../repository/local_complaint_data_source.dart';
import '../repository/remote_complaint_data_source.dart';
import '../../repositories/authority_bridge_service.dart';

/// Offline-first synchronization: complaints are saved locally and enqueued
/// in a sync queue, then automatically pushed to the remote source the moment
/// connectivity returns. Official Case IDs are received back and local data
/// is updated — exactly matching the requested offline flow.
class ComplaintSyncService extends ChangeNotifier {
  ComplaintSyncService({
    required LocalComplaintDataSource local,
    required RemoteComplaintDataSource remote,
  })  : _local = local,
        _remote = remote;

  final LocalComplaintDataSource _local;
  final RemoteComplaintDataSource _remote;
  final ComplaintSyncEngine _engine = ComplaintSyncEngine.instance;

  final Set<String> _pendingIds = {};
  bool _syncing = false;

  bool get isSyncing => _syncing;
  int get pendingCount => _pendingIds.length;
  Set<String> get pendingIds => Set.unmodifiable(_pendingIds);

  void enqueue(String id) {
    _pendingIds.add(id);
    notifyListeners();
  }

  /// Called whenever the app comes online.
  Future<void> syncAll(List<Complaint> localComplaints) async {
    if (_syncing) return;
    _syncing = true;
    notifyListeners();

    try {
      final pending =
          localComplaints.where((c) => _pendingIds.contains(c.id)).toList();
      for (final c in pending) {
        await _syncOne(c);
      }
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  Future<void> _syncOne(Complaint c) async {
    if (!_remote.isOnline) return;
    final op = _engine.decideOperation(c, _remote.hasRemote(c.id));
    switch (op) {
      case SyncOperation.upload:
        final officialCaseId = _remote.upload(c);
        if (officialCaseId != null) {
          c.caseId = officialCaseId;
          // Publish toward the authority portals so supervisors can triage &
          // dispatch this newly-official complaint (full shared loop).
          AuthorityBridgeService.instance
              .publishCitizenUpload(c, officialCaseId);
        }
      case SyncOperation.update:
        _remote.update(c);
      case SyncOperation.confirmParent:
        _remote.applyConfirmation(c.parentComplaintId!, c.confirmationCount);
        _pendingIds.remove(c.id);
        notifyListeners();
        return;
    }
    _pendingIds.remove(c.id);
    await _local.saveComplaints([c]);
    ComplaintEventService.instance.publish(
        ComplaintDomainEvent(type: ComplaintEventType.synced, complaint: c));
    notifyListeners();
  }
}
