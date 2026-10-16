# Progress (updated 2026-10-15, session 2)
## Session 3 — languages + first AI assistant increment
- Added a persisted ten-language selector to first launch and Profile: English, Hindi, Telugu, Tamil, Kannada, Malayalam, Bengali, Marathi, Gujarati, and Punjabi. Existing translated app copy is partial; uncovered strings still fall back to English.
- Added an authenticated, rate-limited `/api/v1/ai/chat` endpoint and `/api/v1/ai/status`; the backend calls an OpenAI-compatible provider only when `AI_API_KEY` is configured. No canned answers are used.
- Added a dashboard **AI Assistant** entry and chat screen. Missing API credentials produce `NOT_CONFIGURED` with setup guidance.
- Added `docs/AI_PROVIDER_SETUP.md` and `docs/AI_SECURITY_AND_PRIVACY.md`.
- Verification: Flutter analyze clean; Windows release rebuilt and launched. Python syntax compilation clean. Backend pytest could not run: Python 3.14 here has no pytest or SQLAlchemy; local API on port 8000 is offline and `backend/.env` is absent, so MySQL/provider runtime calls remain unverified.
- Follow-up from user screenshot: assistant now distinguishes a server connection failure from a reachable API reporting `NOT_CONFIGURED`; shows a Retry action. Rebuilt and relaunched the updated desktop app; current `127.0.0.1:8000` health probe still fails until the backend is started.
- Added `scripts/Start_InfraVision.ps1` and repointed the actual OneDrive Desktop `InfraVision.lnk`: it creates/opens first-run config, prepares the Python 3.13 venv/dependencies, starts FastAPI hidden, waits for `/ready`, then opens the app. PowerShell syntax validated. MySQL password/database are still required once; neither `.env` nor venv exists yet.

## Stage C1 — Security and isolated defects: DONE (verified on SQLite/test adapter + rendered PDF)
- [x] Startup refuses missing/placeholder/short JWT secret and inspector keys; refuses SQLite outside dev/test; refuses missing DATABASE_URL (no silent fallback)
- [x] Inspector auth: constant-time compare, named per-inspector keys (`INSPECTOR_KEYS`), audit actor `inspector:<name>`. Real Inspector contract still pending
- [x] PDF: user text HTML-escaped (no crash on `< > & " '`, tags, empty, long); engine switched ReportLab -> WeasyPrint because ReportLab does not shape Telugu (visually confirmed broken conjuncts)
- [x] Bundled Noto Sans + Noto Sans Telugu (SIL OFL 1.1, `backend/assets/fonts/OFL.txt`); verified embedded in output PDF and visually rendered with correct conjuncts
- [x] Regression tests added (15), 26/26 pass
## Stage C2 — SQL Server migration: CODE DONE, LIVE SERVER NOT TESTED
- [x] ORM uses `citizen` schema (configurable), Unicode types (NVARCHAR), DATETIMEOFFSET variant; DDL compiled against the MSSQL dialect (static check only)
- [x] Reference collision fixed: random reference generated before insert, retry on collision (no shared "PENDING")
- [x] Lazy engine, pool/timeouts configurable, `/ready` health check kept
- [x] `database/migrations/V002__idempotency_hash.sql` written (NOT applied anywhere)
- [ ] Run V001+V002 on the real SQL Server and run the test-suite against it  **(blocked: no SQL Server access here)**
- [ ] Concurrent-create test on SQL Server
## Also fixed from audit (F-ids): F-01, F-02 (foundation), F-04, F-05 (code), F-06, F-07, F-11 (410 on missing file only), F-12, F-13, F-14
## Not started: C3 (stored/versioned PDFs, report_documents table, evidence staging/cleanup), C4 (Flutter compile/APK), C5 (Inspector), C6
