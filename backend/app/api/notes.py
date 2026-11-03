import sqlite3
from typing import Annotated

from fastapi import APIRouter, Depends, Response, status

from app.domain.models import Note, NoteUpdate
from app.errors import NotFoundError
from app.storage import repository as repo
from app.storage.db import get_conn

router = APIRouter(prefix="/notes", tags=["notes"])
Conn = Annotated[sqlite3.Connection, Depends(get_conn)]


@router.get("/{note_id}")
def get_note(note_id: int, conn: Conn) -> Note:
    note = repo.get_note(conn, note_id)
    if note is None:
        raise NotFoundError("Nota", note_id)
    return note


@router.put("/{note_id}")
def update_note(note_id: int, body: NoteUpdate, conn: Conn) -> Note:
    note = repo.update_note(conn, note_id, body.title, body.content)
    if note is None:
        raise NotFoundError("Nota", note_id)
    return note


@router.delete("/{note_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_note(note_id: int, conn: Conn) -> Response:
    if not repo.delete_note(conn, note_id):
        raise NotFoundError("Nota", note_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
