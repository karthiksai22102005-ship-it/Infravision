from datetime import datetime

from pydantic import BaseModel, Field


class RegisterIn(BaseModel):
    email: str = Field(pattern=r"^[^@\s]+@[^@\s]+\.[^@\s]+$", max_length=255)
    full_name: str = Field(min_length=2, max_length=120)
    password: str = Field(min_length=8, max_length=72)


class LoginIn(BaseModel):
    email: str
    password: str


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"


class ComplaintIn(BaseModel):
    category_code: str
    description: str = Field(min_length=10, max_length=2000)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    accuracy_m: float | None = Field(default=None, ge=0, le=100000)
    address: str | None = Field(default=None, max_length=300)


class HistoryOut(BaseModel):
    status: str
    message: str
    created_at: datetime


class EvidenceOut(BaseModel):
    id: int
    content_type: str
    size_bytes: int


class ComplaintOut(BaseModel):
    reference: str
    category_code: str
    category_name: str
    description: str
    latitude: float
    longitude: float
    address: str | None
    status: str
    created_at: datetime
    evidence: list[EvidenceOut] = []
    history: list[HistoryOut] = []


class NearbyOut(BaseModel):
    reference: str
    category_code: str
    latitude: float
    longitude: float
    status: str


class StatusUpdateIn(BaseModel):
    status: str
    citizen_message: str | None = Field(default=None, max_length=300)
    inspector_note: str | None = Field(default=None, max_length=2000)


class NotificationOut(BaseModel):
    id: int
    title: str
    body: str
    kind: str
    is_read: bool
    created_at: datetime


class AIStatusOut(BaseModel):
    status: str
    provider: str | None = None


class AIChatIn(BaseModel):
    message: str = Field(min_length=1, max_length=1000)
    language: str = Field(default="en", max_length=10)


class AIChatOut(BaseModel):
    reply: str
