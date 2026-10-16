# Server Setup

See `docs/HANDOVER.md` in your project for the existing laptop steps. Additions required: remove `create_all` for SQL Server; set strong secrets; run `uvicorn` as a service; open only port 8000 on LAN firewall, never 1433; emulator uses 10.0.2.2, phone uses laptop LAN IP; laptop must stay on and reachable. Full guide to be written after approval and real SQL Server testing.

## Added in session 2
- PDF engine WeasyPrint needs the Pango/HarfBuzz libraries. Linux: `apt install libpango-1.0-0 libpangoft2-1.0-0`. Windows: install the GTK3 runtime (MSYS2 `mingw-w64-x86_64-pango`) and ensure it is on PATH; verify with `python -c "import weasyprint"`. If missing, report generation fails loudly (no silent degraded Telugu).
- Verify ODBC driver: `odbcinst -q -d` (Linux) or ODBC Data Sources (64-bit) on Windows; expected "ODBC Driver 18 for SQL Server".
- Set `ENVIRONMENT=production` on the real server: startup then refuses weak secrets and SQLite.
