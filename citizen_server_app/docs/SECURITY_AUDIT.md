# Security Audit

Good: bcrypt, parameterized ORM queries, 404 on foreign records, inspector notes not in citizen output, random evidence names, no DB credentials in app, evidence not under a static route.
Findings: F-01, F-02 (P0); F-16, F-17, F-18, F-14, F-15 (P2). Also: error handler default FastAPI (no stack traces in prod verified? not tested), CORS not configured (fine for mobile), no TLS, secrets via .env (ok, .gitignore present—verify it lists .env). No dependency vulnerability scan was run.
