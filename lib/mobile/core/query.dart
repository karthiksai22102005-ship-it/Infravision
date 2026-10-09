import '../models/observation.dart';

/// Filter chips of the My Reports screen (§46).
enum ReportFilter {
  all('All'),
  pendingSync('Pending sync'),
  submitted('Submitted'),
  underReview('Under review'),
  resolved('Resolved');

  const ReportFilter(this.label);
  final String label;

  bool matches(Observation o) {
    switch (this) {
      case ReportFilter.all:
        return true;
      case ReportFilter.pendingSync:
        return o.syncState.isPending ||
            o.status == ObservationStatus.pendingSync ||
            o.status == ObservationStatus.savedLocally ||
            o.status == ObservationStatus.uploading;
      case ReportFilter.submitted:
        return o.status == ObservationStatus.serverAccepted ||
            o.syncState == SyncState.serverAccepted ||
            o.syncState == SyncState.synced ||
            o.syncState == SyncState.uploaded;
      case ReportFilter.underReview:
        return o.status == ObservationStatus.underReview;
      case ReportFilter.resolved:
        return o.status == ObservationStatus.resolved;
    }
  }
}

/// One page of a lazily loaded list (§46/§55).
class Page<T> {
  const Page({
    required this.items,
    required this.total,
    required this.offset,
    required this.limit,
  });

  final List<T> items;
  final int total;
  final int offset;
  final int limit;

  bool get hasMore => offset + items.length < total;
  int get loadedCount => offset + items.length;
}
