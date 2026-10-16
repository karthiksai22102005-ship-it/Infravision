# Environment Audit (authoring workspace, 2026-10-15)

This is the Claude cloud workspace, NOT your laptop. I had no access to your SQL Server, Inspector app, or devices.

| Tool | Found |
|---|---|
| Python | 3.13.16 |
| pip, git, node | present (node v22) |
| Java / Gradle | present |
| Flutter / Dart | **missing** |
| Android SDK | **missing** (`ANDROID_HOME` empty) |
| sqlcmd / ODBC | **missing** |
| SQL Server | not reachable from this workspace |

Consequences: backend built and tested here on SQLite; Flutter code, APK build, SQL Server and Inspector steps are unverified.
