# Next session — exact steps
1. To enable the AI assistant, put your provider API key in `backend/.env` as `AI_API_KEY`, set `AI_BASE_URL`/`AI_MODEL` if needed, and restart FastAPI. Until then the in-app assistant stays disabled with a clear setup message.
2. Rebuild the Windows desktop package from the current workspace; the existing `build/windows/x64` CMake cache points to an old `X:` checkout. Then confirm the first-run language picker and Profile language preference.
3. On your laptop: `cd backend; python -m venv .venv; .venv\Scripts\activate; pip install -r requirements.txt`
4. **WeasyPrint on Windows needs the GTK3/Pango runtime** (install "GTK for Windows Runtime" / MSYS2 pango) — see docs/SERVER_SETUP.md. Check: `python -c "import weasyprint; print(weasyprint.__version__)"`.
5. Create `backend/.env` from `.env.example` (real secrets, SQL Server URL). Run V001 then V002 in SSMS on a NEW database (backup first). Start: `uvicorn app.main:app --host 0.0.0.0 --port 8000`; `GET /ready` must return ready.
6. Run `python -m pytest -q` (SQLite adapter) and report any failures.
7. Then tell me: "SQL Server connected" (or paste the error) so I continue with C2 live tests, then C3 (report_documents table, stored/versioned PDFs, evidence staging), C4 (Flutter: needs your `flutter doctor -v` output or an environment with Flutter), C5 (Inspector schema/API).
## Still blocked
SQL Server access, Flutter/Android SDK, Inspector contract, physical device.
