"""Complaint status workflow shared by Citizen and Inspector flows."""

TRANSITIONS = {
    "submitted": {"under_review", "closed"},
    "under_review": {"assigned", "closed"},
    "assigned": {"in_progress", "closed"},
    "in_progress": {"resolved", "closed"},
    "resolved": {"closed", "in_progress"},
    "closed": set(),
}

CITIZEN_MESSAGES = {
    "submitted": "Your report has been received.",
    "under_review": "Our team is reviewing the issue.",
    "assigned": "The complaint has been assigned.",
    "in_progress": "Work on the issue is in progress.",
    "resolved": "The issue has been resolved.",
    "closed": "The complaint has been closed.",
}


def can_transition(current: str, new: str) -> bool:
    return new in TRANSITIONS.get(current, set())
