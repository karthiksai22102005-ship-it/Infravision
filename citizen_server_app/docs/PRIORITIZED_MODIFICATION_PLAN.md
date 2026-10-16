# Prioritized Findings and Modification Plan
Status key: **C** = confirmed (reproduced/executed), **R** = proven by code reading, **U** = unverified assumption/blocked. Nothing here has been changed yet (awaiting your approval).

| ID | P | Status | Finding (evidence) | Required change | Regression test |
|---|---|---|---|---|---|
| F-01 | P0 | R | Default JWT secret and Inspector key `CHANGE_ME*` (`core/config.py`); app starts anyway | Refuse to start when `environment!=development` and secrets are defaults/short | Settings test: prod + default secret raises |
| F-02 | P0 | R | Inspector auth = one shared static key, plain `!=` compare, actor logged as just "inspector" (`core/security.py`) | `hmac.compare_digest`; per-inspector identities/keys or signed tokens; real Inspector role | Auth tests incl. wrong/missing key, audit actor name |
| F-03 | P1 | R | Complaint is committed first, photos uploaded afterwards one by one; success screen shows even if photos fail (`app_state.submit`). Brief requires success only after required server operations | Decide if photo is mandatory. Preferred: staged upload then single finalize call; or show "submitted, photos pending" as a distinct state | Integration test: kill upload mid-way |
| F-04 | P1 | **C** | PDF crashes on `<`/`&` in description (reproduced) | Escape all user text (`xml.sax.saxutils.escape`) in every Paragraph/table cell | PDF test with `<b>`, `&`, `<script>`, Telugu |
| F-05 | P1 | R | ORM models unschematized vs migration `citizen.*`; ORM `String` maps to VARCHAR, migration uses NVARCHAR | Set `schema="citizen"` (configurable); use `Unicode`/`UnicodeText`; test on real SQL Server (Docker/Express) | CI job on disposable SQL Server |
| F-06 | P1 | R | "PENDING" reference collision under concurrency → 500 | Generate reference from a SQL `SEQUENCE` (or unique random+checksum) before insert; handle `IntegrityError` by re-querying | Concurrent-submit test on SQL Server |
| F-07 | P1 | **C** | Telugu font absent; PDF falls back to Helvetica (Telugu glyphs missing) | Bundle Noto Sans Telugu + Latin fallback; visually inspect the output | Render test extracting text/fonts |
| F-08 | P1 | R | PDF generated per request, not stored; no document table; no versioning; no availability state (brief §7) | Add `citizen.report_documents` (id, complaint_id, version, storage_key, sha256, size, created_at); generate after commit via retryable job; snapshot per status change | Doc lifecycle tests |
| F-09 | P1 | U | No Inspector schema/API: complaints live in a separate `citizen` schema | Provide Inspector schema; map or adapt (view/adapter), define status mapping | End-to-end Citizen↔Inspector test |
| F-10 | P1 | U | Flutter code never compiled; plugin versions (camera 0.11, geolocator 12, flutter_map 7…) not checked against current Flutter/AGP | Install Flutter, `flutter create`, `flutter analyze`, fix | `flutter analyze` clean, APK builds |
| F-11 | P1 | R | Evidence write then DB commit, no cleanup: DB failure leaves orphan file; missing file at read time raises unhandled `FileNotFoundError` (500) | Write to temp name, commit, rename; compensating delete; periodic orphan sweep; 404/410 on missing | Fault-injection tests |
| F-12 | P2 | R | Inspector update: `version_id_col` conflicts raise `StaleDataError` → 500; no idempotency for repeated identical status posts | Catch → 409; accept same-status replay idempotently | Concurrent update test |
| F-13 | P2 | R | Idempotency key reused with a *different* body silently returns the old complaint | Store payload hash; 422 on mismatch | Test |
| F-14 | P2 | R | `/complaints/nearby` returns every citizen's complaints (reference, coords, status) to any logged-in user | Decide product intent; if kept, drop references/limit precision/restrict statuses | Authorization test |
| F-15 | P2 | R | Only JPEG/PNG accepted; many phones/gallery produce HEIC/WebP; EXIF (incl. GPS) is stored as-is; whole file read in memory; no decode check | Decode with Pillow, re-encode, strip EXIF, apply orientation; compress client-side | Upload tests per format |
| F-16 | P2 | R | Rate limit is in-memory, auth only, keyed by client IP (all users behind one proxy share it); no lockout | Gateway/Redis limiter, per-account throttling, apply to uploads | Load test |
| F-17 | P2 | R | JWT 24 h, no revocation/refresh/logout, no password reset/email verification | Short access + refresh token, server logout, reset flow | Auth tests |
| F-18 | P2 | R | `usesCleartextTraffic=true` added by `patch_android.py` for all builds | Debug-only network security config; HTTPS for release | Manifest check in CI |
| F-19 | P2 | R | Downloaded PDFs saved permanently in app documents dir named by reference; stay after logout; no `%PDF`/non-empty validation (brief §7.10) | Validate bytes, clear on logout, use cache dir | Widget/unit tests |
| F-20 | P2 | R | Pending photo retry stores file paths; camera temp files may be deleted by OS; 4xx failures are dropped silently | Copy photos to app-private persistent dir; surface permanent failures | Lifecycle test |
| F-21 | P2 | R | No language-selection screen in router (brief lists it as screen 1) and notification tap target / mark-read not wired | Add screen; wire `/notifications/{id}/read` and deep link to complaint | UI tests |
| F-22 | P2 | U | No citizen reply/clarification feature, no push (FCM) | Confirm scope; else document as out of scope | — |
| F-23 | P3 | R | `on_event` deprecated; log format built from raw message (log injection); sequential references guessable | Lifespan handlers; JSON logging lib; keep ownership checks | — |
| F-24 | P1 | U | No backup/restore, monitoring, TLS/proxy, deployment docs | Create docs, then actually test restore | Restore drill |

## Proposed implementation sequence (Stage C, after approval)
1. Safety fixes needing no SQL Server: F-01, F-02, F-04, F-07, F-12, F-13, F-15 + tests.
2. Run backend against real SQL Server (Express/Docker): F-05, F-06, F-11 + migration V002.
3. Report documents + storage interface: F-08, F-03.
4. Install Flutter, compile, fix, add tests: F-10, F-18..F-21.
5. Inspector mapping once schema is supplied: F-09.
6. Backup/restore drill and deployment docs: F-24.
