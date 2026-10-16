"""Citizen report PDFs.

Engine: WeasyPrint (Pango + HarfBuzz). ReportLab was replaced because it does not apply OpenType
shaping, so Telugu conjuncts (e.g. ద్ద, క్రొత్త) rendered broken (verified by rendering both).
Fonts: bundled Noto Sans + Noto Sans Telugu (SIL OFL 1.1, see assets/fonts/OFL.txt).
All user text is HTML-escaped. Citizen-visible data only: inspector notes are never included.
"""
import base64
import os
from html import escape
from pathlib import Path

from app.core.config import get_settings
from app.models.entities import Complaint, utcnow

_FONTS = Path(__file__).resolve().parents[2] / "assets" / "fonts"

_CSS = """
@font-face { font-family: 'NotoSans'; src: url('%(latin)s'); }
@font-face { font-family: 'NotoTelugu'; src: url('%(telugu)s'); }
@page { size: A4; margin: 16mm 18mm; @bottom-right { content: counter(page) ' / ' counter(pages); font-size: 8pt; color: #777; } }
body { font-family: 'NotoSans', 'NotoTelugu', sans-serif; font-size: 10.5pt; color: #111; line-height: 1.45; }
h1 { color: #1F5FE0; font-size: 19pt; text-align: center; margin: 0 0 6mm; }
h2 { color: #1F5FE0; font-size: 13pt; margin: 7mm 0 2mm; }
table { border-collapse: collapse; width: 100%%; }
td, th { border: 0.25pt solid #ccc; padding: 1.5mm 2mm; vertical-align: top; text-align: left; overflow-wrap: anywhere; }
.k { background: #EEF3FF; width: 38mm; }
th { background: #1F5FE0; color: #fff; }
tr { page-break-inside: avoid; }
.desc { white-space: pre-wrap; overflow-wrap: anywhere; }
.ph { display: inline-block; margin: 0 3mm 3mm 0; }
.ph img { width: 52mm; height: 40mm; object-fit: contain; border: 0.25pt solid #ccc; }
.foot { color: #666; font-style: italic; margin-top: 6mm; }
"""


def _e(text: str | None) -> str:
    return escape(text or "", quote=True)


def _data_uri(path: str, ctype: str) -> str:
    with open(path, "rb") as fh:
        return f"data:{ctype};base64," + base64.b64encode(fh.read()).decode()


def build_html(c: Complaint) -> str:
    cat = _e(c.category.name_en) + (f" / {_e(c.category.name_te)}" if c.category.name_te else "")
    acc = f" (+/-{c.accuracy_m:.0f} m)" if c.accuracy_m else ""
    photos = ""
    image_evidence = [e for e in c.evidence if e.content_type in {"image/jpeg", "image/png"}]
    video_count = sum(1 for e in c.evidence if e.content_type.startswith("video/"))
    for e in image_evidence[:4]:
        p = os.path.join(get_settings().evidence_dir, e.file_name)
        if os.path.exists(p):
            photos += f'<span class="ph"><img src="{_data_uri(p, e.content_type)}"></span>'
    video_section = (
        f"<h2>Video evidence</h2><p>{video_count} video file(s) attached to this complaint.</p>"
        if video_count
        else ""
    )
    hist = "".join(
        f"<tr><td>{_e(h.created_at.strftime('%d %b %Y %H:%M'))}</td><td>{_e(h.status.replace('_', ' ').title())}</td>"
        f"<td>{_e(h.citizen_message)}</td></tr>" for h in c.history)
    return f"""<!doctype html><html><head><meta charset="utf-8"><title>InfraVision Citizen {_e(c.reference)}</title></head><body>
<h1>InfraVision Citizen - Complaint Report</h1>
<p><b>Reference:</b> {_e(c.reference)}</p>
<table>
<tr><td class="k">Submitted (UTC)</td><td>{_e(c.created_at.strftime('%d %b %Y, %H:%M'))}</td></tr>
<tr><td class="k">Category</td><td>{cat}</td></tr>
<tr><td class="k">Status</td><td>{_e(c.status.replace('_', ' ').title())}</td></tr>
<tr><td class="k">GPS</td><td>{c.latitude:.5f}, {c.longitude:.5f}{acc}</td></tr>
<tr><td class="k">Address</td><td>{_e(c.address or 'Not available')}</td></tr>
</table>
<h2>Description</h2><div class="desc">{_e(c.description)}</div>
{'<h2>Photographs</h2>' + photos if photos else ''}
{video_section}
<h2>Status history</h2>
<table><thead><tr><th>When (UTC)</th><th>Status</th><th>Update</th></tr></thead><tbody>{hist}</tbody></table>
<p class="foot">Generated {_e(utcnow().strftime('%d %b %Y %H:%M'))} UTC</p>
</body></html>"""


def build_pdf(c: Complaint) -> bytes:
    from weasyprint import CSS, HTML
    from weasyprint.text.fonts import FontConfiguration  # imported lazily: needs Pango (see docs/SERVER_SETUP.md)

    fc = FontConfiguration()  # required for @font-face fonts when CSS objects are passed explicitly
    css = CSS(font_config=fc, string=_CSS % {"latin": (_FONTS / "NotoSans-Regular.ttf").as_uri(),
                             "telugu": (_FONTS / "NotoSansTelugu-Regular.ttf").as_uri()})
    return HTML(string=build_html(c)).write_pdf(stylesheets=[css], font_config=fc)
