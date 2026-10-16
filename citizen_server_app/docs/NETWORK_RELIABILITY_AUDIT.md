# Network Reliability Audit

Positive: 30 s timeout, offline vs server error mapping, stable idempotency key persisted in draft, pending photo retry list. Weak: payload not bound to key (F-13), upload not resumable, retry paths lost if temp files vanish (F-20), no connectivity-aware retry, no backoff. Not tested under real network loss.
