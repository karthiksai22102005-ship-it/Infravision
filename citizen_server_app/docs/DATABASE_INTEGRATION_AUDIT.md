# Database Integration Audit

SQL Server: **not reached**. Migration V001 is additive and uses NVARCHAR/DATETIMEOFFSET, FKs, unique constraints. Problems: ORM/migration schema mismatch (F-05), VARCHAR vs NVARCHAR, `create_all` runs at startup (must be off), no Alembic/version table, grants lack DELETE (fine) but no row-level policy, `is_read` as INT instead of BIT (minor), no table for report documents or storage keys. Concurrency defect in reference generation (F-06). Requires a live-database integration run.
