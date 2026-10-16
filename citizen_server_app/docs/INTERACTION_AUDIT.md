# Interaction Audit

Path: UI → AppState → ApiClient → FastAPI → DB/files. Verified: backend half for register/login/create/list/get/evidence/PDF/notifications/inspector (pytest). **Unverified: every UI control** (app never compiled).
Known broken/missing: PDF with `<`/`&` (F-04); mark-read not wired and notification deep link unverified (F-21); no language screen route (F-21); no citizen reply feature (F-22). Success screen is gated on server response for the complaint, but not for photos (F-03).
