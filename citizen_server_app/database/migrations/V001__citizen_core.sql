-- InfraVision Citizen: V001 core schema (ADDITIVE ONLY, safe to re-run).
-- Run against a NEW database or a dedicated [citizen] schema. Never drops anything.
-- UNVERIFIED against a live SQL Server: review column types against your Inspector schema first.
IF SCHEMA_ID(N'citizen') IS NULL EXEC(N'CREATE SCHEMA citizen');
GO

IF OBJECT_ID(N'citizen.citizens') IS NULL
CREATE TABLE citizen.citizens (
  id INT IDENTITY PRIMARY KEY,
  email NVARCHAR(255) NOT NULL UNIQUE,
  full_name NVARCHAR(120) NOT NULL,
  password_hash NVARCHAR(255) NOT NULL,
  role NVARCHAR(20) NOT NULL DEFAULT 'citizen',
  language NVARCHAR(5) NOT NULL DEFAULT 'en',
  created_at DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET()
);

IF OBJECT_ID(N'citizen.categories') IS NULL
CREATE TABLE citizen.categories (
  id INT IDENTITY PRIMARY KEY,
  code NVARCHAR(40) NOT NULL UNIQUE,
  name_en NVARCHAR(80) NOT NULL,
  name_te NVARCHAR(80) NOT NULL
);

IF OBJECT_ID(N'citizen.complaints') IS NULL
CREATE TABLE citizen.complaints (
  id INT IDENTITY PRIMARY KEY,
  reference NVARCHAR(30) NOT NULL UNIQUE,
  citizen_id INT NOT NULL REFERENCES citizen.citizens(id),
  category_id INT NOT NULL REFERENCES citizen.categories(id),
  description NVARCHAR(MAX) NOT NULL,
  latitude FLOAT NOT NULL CONSTRAINT ck_lat CHECK (latitude BETWEEN -90 AND 90),
  longitude FLOAT NOT NULL CONSTRAINT ck_lng CHECK (longitude BETWEEN -180 AND 180),
  accuracy_m FLOAT NULL,
  address NVARCHAR(300) NULL,
  status NVARCHAR(20) NOT NULL DEFAULT 'submitted',
  version INT NOT NULL DEFAULT 1,
  created_at DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
  updated_at DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET()
);
CREATE INDEX ix_complaints_citizen ON citizen.complaints(citizen_id);
CREATE INDEX ix_complaints_status ON citizen.complaints(status);
CREATE INDEX ix_complaints_geo ON citizen.complaints(latitude, longitude);

IF OBJECT_ID(N'citizen.evidence') IS NULL
CREATE TABLE citizen.evidence (
  id INT IDENTITY PRIMARY KEY,
  complaint_id INT NOT NULL REFERENCES citizen.complaints(id),
  file_name NVARCHAR(80) NOT NULL,
  content_type NVARCHAR(40) NOT NULL,
  size_bytes INT NOT NULL,
  created_at DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET()
);

IF OBJECT_ID(N'citizen.status_history') IS NULL
CREATE TABLE citizen.status_history (
  id INT IDENTITY PRIMARY KEY,
  complaint_id INT NOT NULL REFERENCES citizen.complaints(id),
  status NVARCHAR(20) NOT NULL,
  citizen_message NVARCHAR(300) NOT NULL,
  inspector_note NVARCHAR(MAX) NULL,
  created_at DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET()
);

IF OBJECT_ID(N'citizen.notifications') IS NULL
CREATE TABLE citizen.notifications (
  id INT IDENTITY PRIMARY KEY,
  citizen_id INT NOT NULL REFERENCES citizen.citizens(id),
  complaint_id INT NULL REFERENCES citizen.complaints(id),
  title NVARCHAR(120) NOT NULL,
  body NVARCHAR(300) NOT NULL,
  kind NVARCHAR(20) NOT NULL DEFAULT 'update',
  is_read INT NOT NULL DEFAULT 0,
  created_at DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET()
);

IF OBJECT_ID(N'citizen.idempotency_records') IS NULL
CREATE TABLE citizen.idempotency_records (
  id INT IDENTITY PRIMARY KEY,
  citizen_id INT NOT NULL REFERENCES citizen.citizens(id),
  [key] NVARCHAR(64) NOT NULL,
  complaint_id INT NOT NULL REFERENCES citizen.complaints(id),
  created_at DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
  CONSTRAINT uq_idem UNIQUE (citizen_id, [key])
);

IF OBJECT_ID(N'citizen.audit_events') IS NULL
CREATE TABLE citizen.audit_events (
  id INT IDENTITY PRIMARY KEY,
  actor NVARCHAR(80) NOT NULL,
  action NVARCHAR(60) NOT NULL,
  entity NVARCHAR(60) NOT NULL,
  detail NVARCHAR(300) NULL,
  created_at DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET()
);
GO
-- Least-privilege app login (run as admin, choose your own password, do NOT commit it):
-- CREATE LOGIN citizen_app WITH PASSWORD = '<strong-password>';
-- CREATE USER citizen_app FOR LOGIN citizen_app;
-- GRANT SELECT, INSERT, UPDATE ON SCHEMA::citizen TO citizen_app;
