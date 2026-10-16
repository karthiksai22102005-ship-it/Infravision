# InfraVision Citizen

Flutter citizen app for Android and Windows desktop, backed by a FastAPI service. Citizens can report potholes and civic issues, track report status, and download PDF reports.

## Run on Windows desktop

Once the MySQL database and `backend/.env` are configured, open **InfraVision** from the Windows desktop shortcut. `scripts/Start_InfraVision.ps1` starts the backend quietly, waits for its database readiness check, and then opens the desktop app. Keep using that shortcut; opening the executable directly does not start the backend.

1. Create the MySQL development database and configure the backend in PowerShell (Python 3.10+). MySQL Server 8.4 must be running. Create `infravision_citizen` in Workbench (or run `CREATE DATABASE infravision_citizen CHARACTER SET utf8mb4;`). Copy `backend/.env.example` to `backend/.env`, then set your local MySQL root password and a random JWT secret there. Do not commit `.env`.

   ```powershell
   cd backend
   python -m venv .venv
   .\.venv\Scripts\Activate.ps1
   pip install -r requirements.txt
   # Use the backend/.env values (including your MySQL connection URL).
   uvicorn app.main:app --host 0.0.0.0 --port 8000
   ```

2. In another PowerShell window, run the desktop app:

   ```powershell
   cd citizen_app
   flutter pub get
   flutter run -d windows
   ```

   The desktop app connects to `http://127.0.0.1:8000` by default. Verify the API at <http://127.0.0.1:8000/health> and its database at <http://127.0.0.1:8000/ready>.

   The demo login `demo@infravision.test` / `InfraVisionDemo2026!` belongs only to the SQLite development database and is not created in MySQL. For MySQL, choose **Create an account** in the app to make your own login.

3. Create a standalone Windows build with `flutter build windows`. The executable is under `citizen_app\build\windows\x64\runner\Release\`; copy the whole `Release` directory when distributing it.

## Android APK and laptop server

The API persists reports, report history, and notifications in its configured database; uploaded photos are stored in `backend/evidence_store`. For a physical phone on the same Wi-Fi as this laptop, build the APK with the laptop's current LAN address (shown by `ipconfig`):

```powershell
cd citizen_app
flutter build apk --release --dart-define=API_BASE_URL=http://192.168.2.216:8000
```

Copy `citizen_app\build\app\outputs\flutter-apk\app-release.apk` to `backend\downloads\citizen_app.apk`. With the backend running on `0.0.0.0`, another device on the same Wi-Fi can download it from `http://192.168.2.216:8000/downloads/android.apk`. The downloaded app will use the same laptop API, so reports go to that server and its configured database. Keep the laptop and phone on the same network; this LAN address is not an internet deployment address. For internet use, deploy the API and database to a public host and build the APK with its HTTPS API URL.

The camera preview depends on platform camera support. On a Windows desktop, use the Gallery button to attach photos. Location access depends on Windows location settings; reports can also be entered without coordinates if the backend permits it.

## Project layout

- `backend/` FastAPI API and tests
- `citizen_app/` Flutter Android and Windows app
- `database/` SQL Server production migrations; local MySQL tables are created by the backend in development
- `docs/` handover notes and implementation status

For Android setup and SQL Server configuration, see `docs/HANDOVER.md`. `docs/IMPLEMENTATION_STATUS.md` records checks that have and have not been completed.
