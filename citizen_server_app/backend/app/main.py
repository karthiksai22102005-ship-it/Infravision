import logging
from pathlib import Path

from fastapi import Depends, FastAPI, HTTPException
from fastapi.responses import FileResponse
from sqlalchemy import select, text
from sqlalchemy.orm import Session

from app.api.routes import router
from app.core.config import enforce_settings, get_settings
from app.db.session import Base, SessionLocal, get_db, get_engine
from app.models.entities import Category

DOWNLOADS_DIR = Path(__file__).resolve().parents[1] / "downloads"
ANDROID_APK = DOWNLOADS_DIR / "citizen_app.apk"

logging.basicConfig(level=logging.INFO, format='{"t":"%(asctime)s","lvl":"%(levelname)s","logger":"%(name)s","msg":"%(message)s"}')

CATEGORIES = [
    ("pothole", "Potholes", "గుంతలు"), ("road_damage", "Road Damage", "రోడ్డు నష్టం"),
    ("footpath", "Footpath", "ఫుట్‌పాత్"), ("streetlight", "Streetlight", "వీధి దీపం"),
    ("drainage", "Drainage", "డ్రైనేజీ"), ("manhole", "Manhole", "మ్యాన్‌హోల్"),
    ("traffic_sign", "Traffic Sign", "ట్రాఫిక్ సైన్"), ("road_marking", "Road Marking", "రోడ్డు గుర్తులు"),
    ("other", "Other", "ఇతర"),
]


def seed_categories():
    with SessionLocal() as db:
        have = {c.code for c in db.scalars(select(Category))}
        for code, en, te in CATEGORIES:
            if code not in have:
                db.add(Category(code=code, name_en=en, name_te=te))
        db.commit()


def create_app(create_tables: bool = True) -> FastAPI:
    app = FastAPI(title="InfraVision Citizen API", version="0.1.0")
    app.include_router(router)

    @app.on_event("startup")
    def _startup():
        # Create tables for local development databases. SQL Server production uses versioned migrations.
        s = get_settings()
        enforce_settings(s)  # refuses to start on missing/weak secrets or missing DATABASE_URL
        eng = get_engine()
        if create_tables and (s.is_sqlite or s.database_url.startswith("mysql")):
            Base.metadata.create_all(eng)
        seed_categories()

    @app.get("/health")
    def health():
        return {"status": "ok"}

    @app.get("/downloads/android.apk", include_in_schema=False)
    def android_apk():
        if not ANDROID_APK.is_file():
            raise HTTPException(404, "Android app package has not been published yet")
        return FileResponse(ANDROID_APK, media_type="application/vnd.android.package-archive",
                            filename="InfraVisionCitizen.apk")

    @app.get("/ready")
    def ready(db: Session = Depends(get_db)):
        db.execute(text("SELECT 1"))
        return {"status": "ready"}

    return app


app = create_app()
