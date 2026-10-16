# Implementation changelog
## 2026-10-15 (language preferences)
Added a shared ten-language list (English, Hindi, Telugu, Tamil, Kannada, Malayalam, Bengali, Marathi, Gujarati, Punjabi) to the first-launch welcome and profile preferences. Language selection uses the existing persisted preference and remains available from Profile after onboarding.

## 2026-10-15 (session 2)
Modified: backend/app/core/config.py (validation, no default DB/secret), core/security.py (constant-time, named inspectors), db/session.py (schema-aware Base, lazy engine, timeouts), main.py (enforce at startup, create_all only for SQLite adapter), models/entities.py (Unicode, DATETIMEOFFSET, request_hash), api/routes.py (reference generation, idempotency hash, nearby privacy, 410, inspector replay/409), schemas/dto.py (NearbyOut), services/pdf_report.py (rewritten, WeasyPrint), requirements.txt (reportlab -> weasyprint), tests/test_api.py (+15 tests), citizen_app/lib/core/network/models.dart + features/nearby_issues/nearby_screen.dart (no reference in nearby).
Added: backend/assets/fonts/{NotoSans-Regular.ttf,NotoSansTelugu-Regular.ttf,OFL.txt}, database/migrations/V002__idempotency_hash.sql, .env.example (replaced), docs/* (audit + progress files).
Not touched: Inspector, any database, Flutter beyond the nearby model.
Note: Flutter edit is uncompiled.
