import logging
import math
import os
import secrets
import time
from collections import defaultdict, deque

from fastapi import APIRouter, Depends, File, HTTPException, Request, Response, UploadFile, Header
import httpx
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.security import (current_citizen, hash_password, inspector_auth,
                               make_token, verify_password)
from app.db.session import get_db
from app.models.entities import (AuditEvent, Category, Citizen, Complaint, Evidence,
                                 IdempotencyRecord, Notification, StatusHistory)
from app.schemas.dto import (AIChatIn, AIChatOut, AIStatusOut, ComplaintIn, ComplaintOut, EvidenceOut, HistoryOut, LoginIn,
                             NearbyOut, NotificationOut, RegisterIn, StatusUpdateIn, TokenOut)
from app.services.pdf_report import build_pdf
from app.services.ai_assistant import AIProviderNotConfigured, assistant_status, ask_assistant
from app.services.workflow import CITIZEN_MESSAGES, can_transition

log = logging.getLogger("citizen.api")
router = APIRouter(prefix="/api/v1")

# ---- simple in-memory rate limiter (use Redis/gateway when scaled out) ----
_hits: dict[str, deque] = defaultdict(deque)


def rate_limit(request: Request, limit: int = 10, window: int = 60):
    key = f"{request.client.host if request.client else 'x'}:{request.url.path}"
    now = time.monotonic()
    q = _hits[key]
    while q and now - q[0] > window:
        q.popleft()
    if len(q) >= limit:
        raise HTTPException(429, "Too many requests")
    q.append(now)


# ------------------------------ auth ------------------------------
@router.post("/auth/register", response_model=TokenOut, status_code=201, dependencies=[Depends(rate_limit)])
def register(body: RegisterIn, db: Session = Depends(get_db)):
    email = body.email.lower()
    if db.scalar(select(Citizen).where(Citizen.email == email)):
        raise HTTPException(409, "Email already registered")
    user = Citizen(email=email, full_name=body.full_name, password_hash=hash_password(body.password))
    db.add(user)
    db.commit()
    return TokenOut(access_token=make_token(user.id))


@router.post("/auth/login", response_model=TokenOut, dependencies=[Depends(rate_limit)])
def login(body: LoginIn, db: Session = Depends(get_db)):
    user = db.scalar(select(Citizen).where(Citizen.email == body.email.lower()))
    if not user or not verify_password(body.password, user.password_hash):
        raise HTTPException(401, "Invalid email or password")
    return TokenOut(access_token=make_token(user.id))


@router.get("/me")
def me(user: Citizen = Depends(current_citizen)):
    return {"email": user.email, "full_name": user.full_name, "language": user.language}


# ---------------------------- categories ----------------------------
@router.get("/categories")
def categories(db: Session = Depends(get_db)):
    return [{"code": c.code, "name_en": c.name_en, "name_te": c.name_te}
            for c in db.scalars(select(Category).order_by(Category.id))]


# --------------------------- serialization ---------------------------
def to_out(c: Complaint) -> ComplaintOut:
    return ComplaintOut(
        reference=c.reference, category_code=c.category.code, category_name=c.category.name_en,
        description=c.description, latitude=c.latitude, longitude=c.longitude, address=c.address,
        status=c.status, created_at=c.created_at,
        evidence=[EvidenceOut(id=e.id, content_type=e.content_type, size_bytes=e.size_bytes) for e in c.evidence],
        history=[HistoryOut(status=h.status, message=h.citizen_message, created_at=h.created_at) for h in c.history],
    )


def owned(db: Session, ref: str, user: Citizen) -> Complaint:
    c = db.scalar(select(Complaint).where(Complaint.reference == ref))
    if not c or c.citizen_id != user.id:  # 404 on foreign records: don't leak existence
        raise HTTPException(404, "Complaint not found")
    return c


def _notify(db: Session, c: Complaint, title: str, body: str):
    db.add(Notification(citizen_id=c.citizen_id, complaint_id=c.id, title=title, body=body))


# --------------------------- complaints -----------------------------
@router.post("/complaints", response_model=ComplaintOut, status_code=201)
def create_complaint(body: ComplaintIn, response: Response,
                     idempotency_key: str = Header(min_length=8, max_length=64),
                     user: Citizen = Depends(current_citizen), db: Session = Depends(get_db)):
    prior = db.scalar(select(IdempotencyRecord).where(
        IdempotencyRecord.citizen_id == user.id, IdempotencyRecord.key == idempotency_key))
    if prior:
        response.status_code = 200
        return to_out(db.get(Complaint, prior.complaint_id))
    cat = db.scalar(select(Category).where(Category.code == body.category_code))
    if not cat:
        raise HTTPException(422, "Unknown category")
    c = Complaint(reference="PENDING", citizen_id=user.id, category_id=cat.id, description=body.description,
                  latitude=body.latitude, longitude=body.longitude, accuracy_m=body.accuracy_m,
                  address=body.address, status="submitted")
    c.history.append(StatusHistory(status="submitted", citizen_message=CITIZEN_MESSAGES["submitted"]))
    try:
        db.add(c)
        db.flush()
        c.reference = f"INV-{c.created_at.year}-{c.id:05d}"
        db.add(IdempotencyRecord(citizen_id=user.id, key=idempotency_key, complaint_id=c.id))
        db.add(AuditEvent(actor=f"citizen:{user.id}", action="create", entity=c.reference))
        _notify(db, c, "Report submitted", f"Your complaint {c.reference} was received.")
        db.commit()
    except IntegrityError:  # concurrent retry with the same key
        db.rollback()
        prior = db.scalar(select(IdempotencyRecord).where(
            IdempotencyRecord.citizen_id == user.id, IdempotencyRecord.key == idempotency_key))
        if not prior:
            raise
        response.status_code = 200
        return to_out(db.get(Complaint, prior.complaint_id))
    return to_out(c)


@router.get("/complaints", response_model=list[ComplaintOut])
def my_complaints(status: str | None = None, user: Citizen = Depends(current_citizen),
                  db: Session = Depends(get_db)):
    q = select(Complaint).where(Complaint.citizen_id == user.id).order_by(Complaint.id.desc())
    if status:
        q = q.where(Complaint.status == status)
    return [to_out(c) for c in db.scalars(q).unique()]


@router.get("/complaints/nearby", response_model=list[NearbyOut])
def nearby(lat: float, lng: float, radius_m: float = 2000, user: Citizen = Depends(current_citizen),
           db: Session = Depends(get_db)):
    radius_m = min(max(radius_m, 100), 20000)
    dlat = radius_m / 111_320
    dlng = radius_m / (111_320 * max(math.cos(math.radians(lat)), 0.01))
    rows = db.scalars(select(Complaint).where(
        Complaint.latitude.between(lat - dlat, lat + dlat),
        Complaint.longitude.between(lng - dlng, lng + dlng)).limit(200)).unique()
    return [NearbyOut(reference=c.reference, category_code=c.category.code, latitude=c.latitude,
                      longitude=c.longitude, status=c.status) for c in rows]


@router.get("/complaints/{ref}", response_model=ComplaintOut)
def get_complaint(ref: str, user: Citizen = Depends(current_citizen), db: Session = Depends(get_db)):
    return to_out(owned(db, ref, user))


_IMAGE_MAGIC = {b"\xff\xd8\xff": ("image/jpeg", ".jpg"), b"\x89PNG\r\n\x1a\n": ("image/png", ".png")}


def _evidence_type(data: bytes) -> tuple[str, str] | None:
    for magic, result in _IMAGE_MAGIC.items():
        if data.startswith(magic):
            return result
    if len(data) >= 12 and data[4:8] == b"ftyp":
        brand = data[8:12]
        if brand == b"qt  ":
            return "video/quicktime", ".mov"
        return "video/mp4", ".mp4"
    if data.startswith(b"\x1a\x45\xdf\xa3"):
        return "video/webm", ".webm"
    return None


@router.post("/complaints/{ref}/evidence", response_model=EvidenceOut, status_code=201)
async def upload_evidence(ref: str, file: UploadFile = File(...), user: Citizen = Depends(current_citizen),
                          db: Session = Depends(get_db)):
    s = get_settings()
    c = owned(db, ref, user)
    if len(c.evidence) >= s.max_evidence_per_complaint:
        raise HTTPException(409, "Maximum evidence files reached")
    data = await file.read(s.max_video_evidence_bytes + 1)
    if len(data) > s.max_video_evidence_bytes:
        raise HTTPException(413, "Evidence file exceeds the 50 MB limit")
    detected = _evidence_type(data)
    if detected is None:
        raise HTTPException(415, "Supported evidence: JPEG, PNG, MP4, MOV, or WebM")
    ctype, extension = detected
    limit = s.max_video_evidence_bytes if ctype.startswith("video/") else s.max_evidence_bytes
    if len(data) > limit:
        raise HTTPException(413, "Image evidence exceeds the 8 MB limit")
    os.makedirs(s.evidence_dir, exist_ok=True)
    name = secrets.token_hex(16) + extension
    with open(os.path.join(s.evidence_dir, name), "wb") as fh:
        fh.write(data)
    e = Evidence(complaint_id=c.id, file_name=name, content_type=ctype, size_bytes=len(data))
    db.add(e)
    db.commit()
    return EvidenceOut(id=e.id, content_type=ctype, size_bytes=len(data))


@router.get("/complaints/{ref}/evidence/{eid}")
def get_evidence(ref: str, eid: int, user: Citizen = Depends(current_citizen), db: Session = Depends(get_db)):
    c = owned(db, ref, user)
    e = next((x for x in c.evidence if x.id == eid), None)
    if not e:
        raise HTTPException(404, "Evidence not found")
    with open(os.path.join(get_settings().evidence_dir, e.file_name), "rb") as fh:
        return Response(fh.read(), media_type=e.content_type)


@router.get("/complaints/{ref}/report.pdf")
def report_pdf(ref: str, user: Citizen = Depends(current_citizen), db: Session = Depends(get_db)):
    c = owned(db, ref, user)
    return Response(build_pdf(c), media_type="application/pdf",
                    headers={"Content-Disposition": f'attachment; filename="{c.reference}.pdf"'})


# --------------------------- notifications --------------------------
@router.get("/notifications", response_model=list[NotificationOut])
def notifications(user: Citizen = Depends(current_citizen), db: Session = Depends(get_db)):
    rows = db.scalars(select(Notification).where(Notification.citizen_id == user.id)
                      .order_by(Notification.id.desc()).limit(100))
    return [NotificationOut(id=n.id, title=n.title, body=n.body, kind=n.kind, is_read=bool(n.is_read),
                            created_at=n.created_at) for n in rows]


@router.post("/notifications/{nid}/read", status_code=204)
def mark_read(nid: int, user: Citizen = Depends(current_citizen), db: Session = Depends(get_db)):
    n = db.get(Notification, nid)
    if not n or n.citizen_id != user.id:
        raise HTTPException(404, "Notification not found")
    n.is_read = 1
    db.commit()


# ---------------------------- inspector -----------------------------
@router.post("/inspector/complaints/{ref}/status", response_model=ComplaintOut)
def inspector_update(ref: str, body: StatusUpdateIn, actor: str = Depends(inspector_auth),
                     db: Session = Depends(get_db)):
    c = db.scalar(select(Complaint).where(Complaint.reference == ref))
    if not c:
        raise HTTPException(404, "Complaint not found")
    if body.status not in CITIZEN_MESSAGES:
        raise HTTPException(422, "Unknown status")
    if not can_transition(c.status, body.status):
        raise HTTPException(409, f"Invalid transition {c.status} -> {body.status}")
    msg = body.citizen_message or CITIZEN_MESSAGES[body.status]
    c.status = body.status
    c.history.append(StatusHistory(status=body.status, citizen_message=msg, inspector_note=body.inspector_note))
    db.add(AuditEvent(actor=actor, action="status", entity=c.reference, detail=body.status))
    _notify(db, c, f"Status: {body.status.replace('_', ' ').title()}", f"{c.reference}: {msg}")
    db.commit()  # status, history and notification commit atomically
    return to_out(c)


# ---------------------------- AI assistant --------------------------
@router.get("/ai/status", response_model=AIStatusOut)
def ai_status():
    status = assistant_status()
    return AIStatusOut(
        status=status["status"],
        provider=get_settings().ai_provider if status["status"] == "READY" else None,
    )


@router.post("/ai/chat", response_model=AIChatOut)
def ai_chat(body: AIChatIn):
    if assistant_status()["status"] != "READY":
        raise HTTPException(
            503,
            detail="Online AI assistant is not configured. Set AI_PROVIDER, AI_BASE_URL, and AI_MODEL in backend/.env; AI_API_KEY is also required for OpenAI-compatible providers.",
        )
    try:
        return AIChatOut(reply=ask_assistant(body.message, body.language))
    except AIProviderNotConfigured:
        raise HTTPException(503, "Online AI assistant is not configured")
    except (httpx.HTTPError, KeyError, TypeError, ValueError) as exc:
        log.warning("AI provider request failed (%s)", type(exc).__name__)
        raise HTTPException(502, "AI provider did not return a usable response") from exc
