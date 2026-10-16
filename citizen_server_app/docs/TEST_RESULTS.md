# Test Results (actually executed)
## 2026-10-15 session 3 — AI + desktop rebuild
- `flutter analyze --no-pub`: **No issues found**, including the server-offline/Retry state.
- `flutter build windows --release --no-pub`: **Built successfully** after clearing the stale generated CMake cache and rebuilding through a short drive alias; updated desktop launched.
- `py -3 -m compileall -q app`: **passed**.
- `py -3 -m pytest -q`: **not run**; pytest is not installed in the active Python 3.14 environment. Backend runtime integration also could not be checked because SQLAlchemy is not installed, `backend/.env` is absent, and `127.0.0.1:8000` is offline.
- Manual API health probe: `http://127.0.0.1:8000/health` connection refused; assistant screen now reports this separately from missing AI credentials and offers Retry.
- PowerShell AST parse of `scripts/Start_InfraVision.ps1`: valid. End-to-end launcher remains unverified until the local `.env` and MySQL database are configured.

## 2026-10-15 session 2 — backend, Python 3.12 venv, **SQLite test adapter (NOT SQL Server)**
`python -m pytest -q` -> **26 passed** (11 original + 15 new regression tests).
New tests cover: PDF special characters (6 inputs incl. `<b>`, `&`, quotes, `<script>`, long 1990 chars, newlines), Telugu + mixed text, pagination, bundled fonts embedded, prod refuses placeholder secrets, no silent SQLite fallback, named inspector identity + wrong/missing key + replay idempotency, idempotency-key payload binding, 15 unique references, public-safe nearby, 410 on missing evidence file, MSSQL DDL compile check (static: schema `citizen`, NVARCHAR, DATETIMEOFFSET, FKs).
Visual verification: PDF rasterised with pdftoppm; Latin in Noto Sans, Telugu conjuncts (ద్ద, క్రొత్త, స్త్రీ) shaped correctly; ReportLab output was confirmed broken before the switch.
## Not run / blocked
SQL Server live tests, concurrent creation on SQL Server, Flutter doctor/analyze/test, APK, device tests, Inspector sync, backup restore.
Earlier baseline (session 1, audit): 11 passed on SQLite.
