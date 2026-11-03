"""Acceso a datos de cuadernos y notas. Funciones puras sobre una conexión."""

import sqlite3

from app.domain.models import Note, Notebook, NoteSummary
from app.storage.db import now_iso

_NOTE_SUMMARY_COLS = "id, notebook_id, title, created_at, updated_at"


# --- Cuadernos -------------------------------------------------------------


def list_notebooks(conn: sqlite3.Connection) -> list[Notebook]:
    rows = conn.execute("SELECT * FROM notebooks ORDER BY updated_at DESC, id DESC").fetchall()
    return [Notebook(**row) for row in rows]


def get_notebook(conn: sqlite3.Connection, notebook_id: int) -> Notebook | None:
    row = conn.execute("SELECT * FROM notebooks WHERE id = ?", (notebook_id,)).fetchone()
    return Notebook(**row) if row else None


def create_notebook(conn: sqlite3.Connection, title: str) -> Notebook:
    ts = now_iso()
    cur = conn.execute(
        "INSERT INTO notebooks (title, created_at, updated_at) VALUES (?, ?, ?)",
        (title, ts, ts),
    )
    return Notebook(id=cur.lastrowid, title=title, created_at=ts, updated_at=ts)


def update_notebook(conn: sqlite3.Connection, notebook_id: int, title: str) -> Notebook | None:
    cur = conn.execute(
        "UPDATE notebooks SET title = ?, updated_at = ? WHERE id = ?",
        (title, now_iso(), notebook_id),
    )
    return get_notebook(conn, notebook_id) if cur.rowcount else None


def delete_notebook(conn: sqlite3.Connection, notebook_id: int) -> bool:
    return conn.execute("DELETE FROM notebooks WHERE id = ?", (notebook_id,)).rowcount > 0


# --- Notas -----------------------------------------------------------------


def list_notes(conn: sqlite3.Connection, notebook_id: int) -> list[NoteSummary]:
    rows = conn.execute(
        f"SELECT {_NOTE_SUMMARY_COLS} FROM notes WHERE notebook_id = ? "
        "ORDER BY updated_at DESC, id DESC",
        (notebook_id,),
    ).fetchall()
    return [NoteSummary(**row) for row in rows]


def get_note(conn: sqlite3.Connection, note_id: int) -> Note | None:
    row = conn.execute("SELECT * FROM notes WHERE id = ?", (note_id,)).fetchone()
    return Note(**row) if row else None


def create_note(conn: sqlite3.Connection, notebook_id: int, title: str, content: str) -> Note:
    ts = now_iso()
    cur = conn.execute(
        "INSERT INTO notes (notebook_id, title, content, created_at, updated_at) "
        "VALUES (?, ?, ?, ?, ?)",
        (notebook_id, title, content, ts, ts),
    )
    return Note(
        id=cur.lastrowid,
        notebook_id=notebook_id,
        title=title,
        content=content,
        created_at=ts,
        updated_at=ts,
    )


def update_note(
    conn: sqlite3.Connection, note_id: int, title: str | None, content: str | None
) -> Note | None:
    current = get_note(conn, note_id)
    if current is None:
        return None
    conn.execute(
        "UPDATE notes SET title = ?, content = ?, updated_at = ? WHERE id = ?",
        (
            title if title is not None else current.title,
            content if content is not None else current.content,
            now_iso(),
            note_id,
        ),
    )
    return get_note(conn, note_id)


def delete_note(conn: sqlite3.Connection, note_id: int) -> bool:
    return conn.execute("DELETE FROM notes WHERE id = ?", (note_id,)).rowcount > 0
