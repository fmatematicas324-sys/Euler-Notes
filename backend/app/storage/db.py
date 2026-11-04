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


# Migraciones posteriores a schema.sql (v0.1). La posición en la lista es la
# versión (`PRAGMA user_version`); nunca se reordenan ni se editan, solo se añaden.
_MIGRATIONS: tuple[str, ...] = (
    # 1 · v0.2: portada de cuaderno, papel de nota y biblioteca de PDF.
    """
    ALTER TABLE notebooks ADD COLUMN cover TEXT NOT NULL DEFAULT 'classic';
    ALTER TABLE notes ADD COLUMN paper TEXT NOT NULL DEFAULT 'blank';
    CREATE TABLE IF NOT EXISTS documents (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        filename    TEXT    NOT NULL,
        size        INTEGER NOT NULL,
        pages       INTEGER NOT NULL,
        created_at  TEXT    NOT NULL
    );
    """,
    # 2 · v0.3: dibujos a mano (bloques ```ink de las notas).
    """
    CREATE TABLE IF NOT EXISTS drawings (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        note_id     INTEGER NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
        width       REAL    NOT NULL,
        height      REAL    NOT NULL,
        strokes     TEXT    NOT NULL DEFAULT '[]',
        created_at  TEXT    NOT NULL,
        updated_at  TEXT    NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_drawings_note_id ON drawings(note_id);
    """,
)


def init_db(db_path: Path) -> None:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    documents_dir(db_path).mkdir(exist_ok=True)
    conn = connect(db_path)
    try:
        conn.executescript(_SCHEMA_PATH.read_text(encoding="utf-8"))
        version = conn.execute("PRAGMA user_version").fetchone()[0]
        for number, script in enumerate(_MIGRATIONS[version:], start=version + 1):
            conn.executescript(f"BEGIN;\n{script}\nPRAGMA user_version = {number};\nCOMMIT;")
    finally:
        conn.close()


def documents_dir(db_path: Path) -> Path:
    """Carpeta de los PDF importados, junto a la base de datos."""
    return db_path.parent / "documents"


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
