"""Conexión SQLite (stdlib `sqlite3`) e inicialización del esquema."""

import sqlite3
from collections.abc import Iterator
from datetime import UTC, datetime
from pathlib import Path

from fastapi import Request

_SCHEMA_PATH = Path(__file__).with_name("schema.sql")


def connect(db_path: Path) -> sqlite3.Connection:
    # FastAPI puede ejecutar la dependencia y el endpoint en hilos distintos del pool;
    # cada petición usa su propia conexión, así que desactivar la comprobación es seguro.
    conn = sqlite3.connect(db_path, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def init_db(db_path: Path) -> None:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    with connect(db_path) as conn:
        conn.executescript(_SCHEMA_PATH.read_text(encoding="utf-8"))
    conn.close()


def get_conn(request: Request) -> Iterator[sqlite3.Connection]:
    """Dependencia FastAPI: una conexión por petición, con commit al terminar sin errores."""
    conn = connect(request.app.state.db_path)
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def now_iso() -> str:
    return datetime.now(UTC).isoformat(timespec="microseconds")
