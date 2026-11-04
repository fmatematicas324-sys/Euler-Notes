"""Dibujos a mano alzada de las notas (bloques ```ink)."""

import sqlite3
from typing import Annotated

from fastapi import APIRouter, Depends, Response, status

from app.domain.models import Drawing, DrawingCreate, DrawingUpdate
from app.errors import NotFoundError
from app.storage import repository as repo
from app.storage.db import get_conn

router = APIRouter(tags=["drawings"])
Conn = Annotated[sqlite3.Connection, Depends(get_conn)]


@router.post("/notes/{note_id}/drawings", status_code=status.HTTP_201_CREATED)
def create_drawing(note_id: int, body: DrawingCreate, conn: Conn) -> Drawing:
    if repo.get_note(conn, note_id) is None:
        raise NotFoundError("Nota", note_id)
    return repo.create_drawing(conn, note_id, body.width, body.height, body.strokes)


@router.get("/drawings/{drawing_id}")
def get_drawing(drawing_id: int, conn: Conn) -> Drawing:
    drawing = repo.get_drawing(conn, drawing_id)
    if drawing is None:
        raise NotFoundError("Dibujo", drawing_id)
    return drawing


@router.put("/drawings/{drawing_id}")
def update_drawing(drawing_id: int, body: DrawingUpdate, conn: Conn) -> Drawing:
    drawing = repo.update_drawing(conn, drawing_id, body.width, body.height, body.strokes)
    if drawing is None:
        raise NotFoundError("Dibujo", drawing_id)
    return drawing


@router.delete("/drawings/{drawing_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_drawing(drawing_id: int, conn: Conn) -> Response:
    if not repo.delete_drawing(conn, drawing_id):
        raise NotFoundError("Dibujo", drawing_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
