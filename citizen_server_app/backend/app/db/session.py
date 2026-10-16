from sqlalchemy import MetaData, create_engine
from sqlalchemy.orm import DeclarativeBase, sessionmaker

from app.core.config import ConfigError, get_settings

_s = get_settings()
# SQL Server uses a schema; MySQL uses the selected database as its namespace.
_is_mysql = _s.database_url.startswith("mysql")
SCHEMA = None if (_s.is_sqlite or _is_mysql or not _s.database_url) else _s.db_schema


class Base(DeclarativeBase):
    metadata = MetaData(schema=SCHEMA)


def make_engine(url: str | None = None):
    s = get_settings()
    url = url or s.database_url
    if not url:
        raise ConfigError("DATABASE_URL is not set")
    kwargs: dict = {"pool_pre_ping": True}
    if url.startswith("sqlite"):
        kwargs["connect_args"] = {"check_same_thread": False}
    elif url.startswith("mysql"):
        kwargs.update(pool_size=s.db_pool_size, max_overflow=s.db_max_overflow, pool_recycle=1800,
                      pool_timeout=s.db_connect_timeout_s,
                      connect_args={"connect_timeout": s.db_connect_timeout_s})
    else:
        kwargs.update(pool_size=s.db_pool_size, max_overflow=s.db_max_overflow, pool_recycle=1800,
                      pool_timeout=s.db_connect_timeout_s,
                      connect_args={"timeout": s.db_connect_timeout_s})  # pyodbc login/query timeout
    return create_engine(url, **kwargs)


_engine = None
SessionLocal = sessionmaker(autoflush=False, expire_on_commit=False)


def get_engine():
    """Created lazily so a bad/missing configuration fails at startup with a clear message."""
    global _engine
    if _engine is None:
        _engine = make_engine()
        SessionLocal.configure(bind=_engine)
    return _engine


def get_db():
    get_engine()
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
