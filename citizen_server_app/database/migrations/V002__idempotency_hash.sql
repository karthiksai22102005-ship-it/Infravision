-- InfraVision Citizen: V002 (ADDITIVE ONLY, safe to re-run). UNVERIFIED against a live SQL Server.
-- Purpose: bind an Idempotency-Key to its request payload so a reused key with a different body is rejected.
-- Take a full backup BEFORE running (see docs/BACKUP_AND_RECOVERY_PLAN.md). Rollback: the column is nullable,
-- the app tolerates NULL, so rollback = ALTER TABLE citizen.idempotency_records DROP COLUMN request_hash.
IF COL_LENGTH(N'citizen.idempotency_records', N'request_hash') IS NULL
  ALTER TABLE citizen.idempotency_records ADD request_hash NVARCHAR(64) NULL;
GO
