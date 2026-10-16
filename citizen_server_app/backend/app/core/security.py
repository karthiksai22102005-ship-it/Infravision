import hmac
from datetime import datetime, timedelta, timezone

import jwt
from fastapi import Depends, Header, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from passlib.context import CryptContext
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.db.session import get_db
from app.models.entities import Citizen

pwd = CryptContext(schemes=["bcrypt"], deprecated="auto")
bearer = HTTPBearer(auto_error=False)


def hash_password(p: str) -> str:
    return pwd.hash(p)


def verify_password(p: str, h: str) -> bool:
    return pwd.verify(p, h)


def make_token(citizen_id: int) -> str:
    s = get_settings()
    exp = datetime.now(timezone.utc) + timedelta(minutes=s.jwt_minutes)
    return jwt.encode({"sub": str(citizen_id), "exp": exp}, s.jwt_secret, algorithm="HS256")


def current_citizen(
    cred: HTTPAuthorizationCredentials | None = Depends(bearer),
    db: Session = Depends(get_db),
) -> Citizen:
    if cred is None:
        raise HTTPException(401, "Not authenticated")
    try:
        data = jwt.decode(cred.credentials, get_settings().jwt_secret, algorithms=["HS256"])
    except jwt.PyJWTError:
        raise HTTPException(401, "Invalid or expired token")
    user = db.get(Citizen, int(data["sub"]))
    if not user:
        raise HTTPException(401, "Unknown user")
    return user


def inspector_auth(x_inspector_key: str = Header(default="")) -> str:
    """Returns the NAME of the inspector whose key matched (constant-time comparison).

    Foundation only: the real Inspector authentication contract is not yet available.
    """
    supplied = x_inspector_key.encode()
    matched = None
    for name, key in get_settings().inspector_key_map().items():
        if hmac.compare_digest(supplied, key.encode()):  # no early exit: constant work per key
            matched = name
    if not supplied or matched is None:
        raise HTTPException(403, "Inspector authorization required")
    return f"inspector:{matched}"
