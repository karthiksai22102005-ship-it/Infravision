# Implementation Status (2026-10-15, after Stage C1/C2 code)
| Area | State | Evidence |
|---|---|---|
| Language preferences | 10 Indian languages selectable on first launch and in Profile; selected code persists. Existing app copy is only partially localized and falls back to English. | `citizen_app/lib/core/localization/languages.dart`; `flutter analyze --no-pub` clean |
| AI assistant | Provider-backed chat and dashboard entry implemented; API key remains unconfigured, so assistant correctly displays disabled state until server setup. | `backend/app/services/ai_assistant.py`; `docs/AI_PROVIDER_SETUP.md` |
| Windows startup | Desktop shortcut now runs a hidden backend launcher, waits for database readiness, then starts the app. First run needs MySQL password/database setup; launcher prepares Python 3.13 venv and packages. | `scripts/Start_InfraVision.ps1`; desktop `InfraVision.lnk` |
| Secret/config validation, no SQLite fallback | Done | tests (SQLite adapter) |
| Inspector auth foundation (named keys, constant-time) | Done; real Inspector contract **pending** | tests |
| PDF special characters + English/Telugu rendering | Done | rendered & viewed; tests |
| Complaint reference concurrency | Code fixed; **SQL Server concurrency untested** | sequential uniqueness test only |
| SQL Server schema/types in ORM | Done statically (MSSQL DDL compile) | **no live DB** |
| V002 migration | Written, **not applied** | — |
| Nearby privacy | Done (backend + app model) | API tests; Windows app compiled |
| Stored/versioned PDFs, report_documents, evidence staging | **Not started (C3)** | — |
| Flutter Windows desktop | Rebuilt and launched with current language + AI UI | `citizen_app/build/windows/x64/runner/Release/citizen_app.exe`; local API at `127.0.0.1:8000` is currently offline |
| Android APK/devices | **Not verified** | Android licenses not accepted; no Android build/device check |
| Windows PDF rendering | **Blocked on host setup** | WeasyPrint cannot load `libgobject-2.0-0`; 8 PDF tests fail until GTK runtime is installed |
| Inspector sync | **Blocked** (no contract) | — |
| Backups | **Plan only, untested** | — |
