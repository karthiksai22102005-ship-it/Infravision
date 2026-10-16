# Backup and Recovery Plan (PROPOSAL, nothing operational)

Proposal only; **no backup has been configured or restored.**
- SQL Server: FULL nightly, DIFF every 6 h, LOG every 15 min if FULL recovery model is chosen; `CHECKSUM`, `RESTORE VERIFYONLY` after each.
- Files (evidence, PDFs): nightly snapshot + sync to a second location; keep DB backup and file snapshot timestamps aligned.
- Proposed RPO 15 min (DB) / 24 h (files, tunable), RTO 4 h.
- Consistency: after restore run an orphan/missing-file reconciliation script (DB rows without files; files without rows).
- Encrypt backups, restrict to a backup account, alert on failure and disk <20 %.
- Test restore monthly into a scratch database; record results in TEST_RESULTS.md.
