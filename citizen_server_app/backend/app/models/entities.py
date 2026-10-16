from datetime import datetime, timezone

from sqlalchemy import (CheckConstraint, DateTime, Float, ForeignKey, Index,
                        Integer, Unicode, UnicodeText, UniqueConstraint)
from sqlalchemy.dialects import mssql
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.session import Base


TS = DateTime(timezone=True).with_variant(mssql.DATETIMEOFFSET(), "mssql")


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class Citizen(Base):
    __tablename__ = "citizens"
    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(Unicode(255), unique=True, index=True)
    full_name: Mapped[str] = mapped_column(Unicode(120))
    password_hash: Mapped[str] = mapped_column(Unicode(255))
    role: Mapped[str] = mapped_column(Unicode(20), default="citizen")
    language: Mapped[str] = mapped_column(Unicode(5), default="en")
    created_at: Mapped[datetime] = mapped_column(TS, default=utcnow)


class Category(Base):
    __tablename__ = "categories"
    id: Mapped[int] = mapped_column(primary_key=True)
    code: Mapped[str] = mapped_column(Unicode(40), unique=True)
    name_en: Mapped[str] = mapped_column(Unicode(80))
    name_te: Mapped[str] = mapped_column(Unicode(80))


class Complaint(Base):
    __tablename__ = "complaints"
    __table_args__ = (
        CheckConstraint("latitude BETWEEN -90 AND 90", name="ck_lat"),
        CheckConstraint("longitude BETWEEN -180 AND 180", name="ck_lng"),
        Index("ix_complaints_geo", "latitude", "longitude"),
    )
    id: Mapped[int] = mapped_column(primary_key=True)
    reference: Mapped[str] = mapped_column(Unicode(30), unique=True, index=True)
    citizen_id: Mapped[int] = mapped_column(ForeignKey("citizens.id"), index=True)
    category_id: Mapped[int] = mapped_column(ForeignKey("categories.id"))
    description: Mapped[str] = mapped_column(UnicodeText)
    latitude: Mapped[float] = mapped_column(Float)
    longitude: Mapped[float] = mapped_column(Float)
    accuracy_m: Mapped[float | None] = mapped_column(Float, nullable=True)
    address: Mapped[str | None] = mapped_column(Unicode(300), nullable=True)
    status: Mapped[str] = mapped_column(Unicode(20), default="submitted", index=True)
    version: Mapped[int] = mapped_column(Integer, default=1)  # optimistic concurrency
    created_at: Mapped[datetime] = mapped_column(TS, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(TS, default=utcnow, onupdate=utcnow)

    category: Mapped[Category] = relationship(lazy="joined")
    evidence: Mapped[list["Evidence"]] = relationship(back_populates="complaint", cascade="all,delete-orphan")
    history: Mapped[list["StatusHistory"]] = relationship(
        back_populates="complaint", cascade="all,delete-orphan", order_by="StatusHistory.id")
    __mapper_args__ = {"version_id_col": version}


class Evidence(Base):
    __tablename__ = "evidence"
    id: Mapped[int] = mapped_column(primary_key=True)
    complaint_id: Mapped[int] = mapped_column(ForeignKey("complaints.id"), index=True)
    file_name: Mapped[str] = mapped_column(Unicode(80))  # server-generated, private store
    content_type: Mapped[str] = mapped_column(Unicode(40))
    size_bytes: Mapped[int] = mapped_column(Integer)
    created_at: Mapped[datetime] = mapped_column(TS, default=utcnow)
    complaint: Mapped[Complaint] = relationship(back_populates="evidence")


class StatusHistory(Base):
    __tablename__ = "status_history"
    id: Mapped[int] = mapped_column(primary_key=True)
    complaint_id: Mapped[int] = mapped_column(ForeignKey("complaints.id"), index=True)
    status: Mapped[str] = mapped_column(Unicode(20))
    citizen_message: Mapped[str] = mapped_column(Unicode(300))  # visible to citizen
    inspector_note: Mapped[str | None] = mapped_column(UnicodeText, nullable=True)  # private
    created_at: Mapped[datetime] = mapped_column(TS, default=utcnow)
    complaint: Mapped[Complaint] = relationship(back_populates="history")


class Notification(Base):
    __tablename__ = "notifications"
    id: Mapped[int] = mapped_column(primary_key=True)
    citizen_id: Mapped[int] = mapped_column(ForeignKey("citizens.id"), index=True)
    complaint_id: Mapped[int | None] = mapped_column(ForeignKey("complaints.id"), nullable=True)
    title: Mapped[str] = mapped_column(Unicode(120))
    body: Mapped[str] = mapped_column(Unicode(300))
    kind: Mapped[str] = mapped_column(Unicode(20), default="update")
    is_read: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(TS, default=utcnow)


class IdempotencyRecord(Base):
    __tablename__ = "idempotency_records"
    __table_args__ = (UniqueConstraint("citizen_id", "key", name="uq_idem"),)
    id: Mapped[int] = mapped_column(primary_key=True)
    citizen_id: Mapped[int] = mapped_column(ForeignKey("citizens.id"))
    key: Mapped[str] = mapped_column(Unicode(64))
    complaint_id: Mapped[int] = mapped_column(ForeignKey("complaints.id"))
    request_hash: Mapped[str | None] = mapped_column(Unicode(64), nullable=True)  # binds key to payload
    created_at: Mapped[datetime] = mapped_column(TS, default=utcnow)


class AuditEvent(Base):
    __tablename__ = "audit_events"
    id: Mapped[int] = mapped_column(primary_key=True)
    actor: Mapped[str] = mapped_column(Unicode(80))
    action: Mapped[str] = mapped_column(Unicode(60))
    entity: Mapped[str] = mapped_column(Unicode(60))
    detail: Mapped[str | None] = mapped_column(Unicode(300), nullable=True)
    created_at: Mapped[datetime] = mapped_column(TS, default=utcnow)
