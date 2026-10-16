# Handover: run it on your laptop

## 1. Backend (Windows PowerShell)
```powershell
cd InfraVisionCitizen\backend
python -m venv .venv ; .\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python -m pytest -q                      # should show 11 passed
copy ..\.env.example .env                # then edit values
```
Quick start with no SQL Server: leave `DATABASE_URL` unset (uses local SQLite file) and run:
```powershell
uvicorn app.main:app --host 0.0.0.0 --port 8000
```
API docs: http://localhost:8000/docs

## 2. Use your SQL Server
1. Install "ODBC Driver 18 for SQL Server".
2. Create a **new** database (or schema) for Citizen. Do not touch the Inspector database.
3. Run `database/migrations/V001__citizen_core.sql` in SSMS, then create the limited login (commented at the bottom).
4. Enable TCP/IP on port 1433 in SQL Server Configuration Manager; allow it only on your LAN in Windows Firewall.
5. Put the real `DATABASE_URL` in `backend/.env`. Check `GET /ready` returns `ready`.
Note: with SQL Server, set `create_tables=False` in `create_app` (or remove `create_all`) so only the SQL script manages the schema.

## 3. Flutter app
```powershell
cd InfraVisionCitizen
flutter create --org com.infravision --project-name citizen_app citizen_app   # keeps existing lib/, adds android/
python scripts\patch_android.py citizen_app
cd citizen_app
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=API_BASE_URL=http://<LAPTOP-LAN-IP>:8000
flutter build apk --debug --dart-define=API_BASE_URL=http://<LAPTOP-LAN-IP>:8000
```
Phone and laptop must be on the same Wi-Fi. Emulator uses `http://10.0.2.2:8000` (the default).
Debug APK output: `citizen_app\build\app\outputs\flutter-apk\app-debug.apk`. A release APK needs your own signing key.

## 4. Inspector integration
Inspector calls `POST /api/v1/inspector/complaints/{reference}/status` with header `X-Inspector-Key` and JSON
`{"status":"under_review","citizen_message":"...","inspector_note":"private"}`.
Valid flow: submitted -> under_review -> assigned -> in_progress -> resolved -> closed.
Send me the Inspector schema or API to map to its existing complaint table.

## 5. Security reminders
Change `JWT_SECRET` and `INSPECTOR_API_KEY`; use HTTPS before any public deployment; remove cleartext traffic
from the manifest for production; never put DB credentials in the app.
