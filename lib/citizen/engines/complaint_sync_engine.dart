import '../models/complaint.dart';

/// Offline-first synchronization decisions. Pure logic used by
/// [ComplaintSyncService] to reconcile the local and remote data sources.
class ComplaintSyncEngine {
  ComplaintSyncEngine._();

  static final ComplaintSyncEngine instance = ComplaintSyncEngine._();

  /// Which complaints still need to be pushed to the remote source.
  List<Complaint> pendingItems(List<Complaint> all, Set<String> syncedIds) =>
      all.where((c) => !syncedIds.contains(c.id)).toList();

  /// Decide the operation needed for a single complaint when going online.
  SyncOperation decideOperation(Complaint c, bool hasRemote) {
    // A complaint with a parent is a merged confirmation -> bump the parent.
    if (c.parentComplaintId != null) {
      return SyncOperation.confirmParent;
    }
    if (hasRemote) return SyncOperation.update;
    return SyncOperation.upload;
  }

  bool mergeIncoming(Complaint local, Complaint remote) {
    // Keep remote authoritative for status/timeline, but preserve local id.
    var changed = false;
    if (remote.status != local.status) {
      local.status = remote.status;
      changed = true;
    }
    if (!remote.timeline.every(local.timeline.contains)) {
      local.timeline = remote.timeline;
      changed = true;
    }
    local.confirmationCount = remote.confirmationCount;
    local.priorityScore = remote.priorityScore;
    local.priority = remote.priority;
    local.slaDeadline = remote.slaDeadline;
    local.updatedAt = remote.updatedAt;
    return changed;
  }
}

/// Kind of synchronization required for a complaint when connectivity returns.
enum SyncOperation {
  upload('upload'),
  update('update'),
  confirmParent('confirm_parent');

  const SyncOperation(this.key);
  final String key;
}

