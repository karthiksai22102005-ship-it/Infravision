# InfraVision Citizen

Flutter Citizen client for reporting and tracking municipal infrastructure issues.

## Connect a phone to the backend

1. Start FastAPI on the development computer, bound to all network interfaces:
   `uvicorn app.main:app --host 0.0.0.0 --port 8000` (run from `backend/`).
2. Put the phone and computer on the same trusted Wi-Fi network and allow port 8000 through the computer firewall.
3. In the app, open **Profile → Server connection** and enter `http://<computer-lan-ip>:8000`.
4. For a deployed server, use its HTTPS URL. Do not expose a development server directly to the public internet.

The default Android URL `10.0.2.2` is for the emulator. The server must be reachable for sign-in, online AI, report submission, and status refresh. Local report preparation and on-device photo analysis do not require the API.

## Optional online AI

Set `AI_API_KEY`, `AI_BASE_URL`, and `AI_MODEL` in `backend/.env`, then restart FastAPI. Keep provider credentials on the backend; never put them in Flutter source or app assets. With a missing or invalid provider configuration, the AI assistant reports an error and does not fabricate an answer.

## Release signing

Release builds no longer use the debug signing key. Before building a distributable release, set these environment variables to a keystore and credentials you control:

- `ANDROID_KEYSTORE_PATH`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

Do not commit the keystore or its passwords. A release build without these settings is intentionally not distributable.
