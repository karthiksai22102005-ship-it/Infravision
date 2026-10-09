/// ISSUE LIFECYCLE STATE MACHINE — replaces scattered status updates with a
/// declarative transition matrix driven by real events and evidence.
/// Existing simple statuses keep working; this layer adds intelligence.
library;

import '../models/issue_event.dart';
import '../models/physical_issue.dart';

class IssueLifecycleEngine {
  IssueLifecycleEngine._();
  static final IssueLifecycleEngine instance = IssueLifecycleEngine._();

  /// Allowed transitions per state.
  static const Map<IssueLifecycleState, Set<IssueLifecycleState>> _transitions = {
    IssueLifecycleState.candidate: {
      IssueLifecycleState.identified,
      IssueLifecycleState.verificationRequired,
      IssueLifecycleState.closed
    },
    IssueLifecycleState.identified: {
      IssueLifecycleState.verificationRequired,
      IssueLifecycleState.verified,
      IssueLifecycleState.assigned
    },
    IssueLifecycleState.verificationRequired: {
      IssueLifecycleState.verified,
      IssueLifecycleState.persistent,
      IssueLifecycleState.escalated
    },
    IssueLifecycleState.verified: {IssueLifecycleState.assigned, IssueLifecycleState.closed},
    IssueLifecycleState.assigned: {IssueLifecycleState.inProgress, IssueLifecycleState.escalated},
    IssueLifecycleState.inProgress: {
      IssueLifecycleState.resolutionSubmitted,
      IssueLifecycleState.escalated
    },
    IssueLifecycleState.resolutionSubmitted: {
      IssueLifecycleState.reverificationRequired,
      IssueLifecycleState.escalated
    },
    IssueLifecycleState.reverificationRequired: {
      IssueLifecycleState.resolved,
      IssueLifecycleState.persistent
    },
    IssueLifecycleState.resolved: {IssueLifecycleState.closed, IssueLifecycleState.persistent},
    IssueLifecycleState.persistent: {
      IssueLifecycleState.identified,
      IssueLifecycleState.assigned,
      IssueLifecycleState.escalated
    },
    IssueLifecycleState.escalated: {IssueLifecycleState.assigned, IssueLifecycleState.inProgress},
    IssueLifecycleState.closed: {},
  };

  bool canTransition(IssueLifecycleState from, IssueLifecycleState to) =>
      _transitions[from]!.contains(to);

  /// Returns the new state, or null when the transition is illegal.
  IssueLifecycleState? transition(
          IssueLifecycleState current, IssueLifecycleState next) =>
      canTransition(current, next) ? next : null;

  /// Drives the state machine from a real-world [IssueEventType].
  IssueLifecycleState? transitionForEvent(
      IssueLifecycleState current, IssueEventType event) {
    final target = switch (event) {
      IssueEventType.newIssueCreated => IssueLifecycleState.candidate,
      IssueEventType.matchedExisting => IssueLifecycleState.identified,
      IssueEventType.matchUncertain => IssueLifecycleState.verificationRequired,
      IssueEventType.fieldVerified => IssueLifecycleState.verified,
      IssueEventType.taskAssigned => IssueLifecycleState.assigned,
      IssueEventType.workStarted => IssueLifecycleState.inProgress,
      IssueEventType.resolutionSubmitted =>
        IssueLifecycleState.resolutionSubmitted,
      IssueEventType.verificationPassed => IssueLifecycleState.resolved,
      IssueEventType.verificationFailed => IssueLifecycleState.persistent,
      IssueEventType.escalated => IssueLifecycleState.escalated,
      IssueEventType.reopened => IssueLifecycleState.persistent,
      IssueEventType.closed => IssueLifecycleState.closed,
      _ => null,
    };
    if (target == null) return null;
    return transition(current, target);
  }
}
