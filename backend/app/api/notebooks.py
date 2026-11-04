import sqlite3
from typing import Annotated

from fastapi import APIRouter, Depends, Response, status

from app.domain.models import Note, Notebook, NotebookIn, NotebookUpdate, NoteCreate, NoteSummary
from app.errors import NotFoundError
from app.storage import repository as repo
from app.storage.db import get_conn

router = APIRouter(prefix="/notebooks", tags=["notebooks"])
Conn = Annotated[sqlite3.Connection, Depends(get_conn)]


def _require_notebook(conn: sqlite3.Connection, notebook_id: int) -> Notebook:
    notebook = repo.get_notebook(conn, notebook_id)
    if notebook is None:
        raise NotFoundError("Cuaderno", notebook_id)
    return notebook


@router.get("")
def list_notebooks(conn: Conn) -> list[Notebook]:
    return repo.list_notebooks(conn)


@router.post("", status_code=status.HTTP_201_CREATED)
def create_notebook(body: NotebookIn, conn: Conn) -> Notebook:
    return repo.create_notebook(conn, body.title, body.cover)


@router.get("/{notebook_id}")
def get_notebook(notebook_id: int, conn: Conn) -> Notebook:
    return _require_notebook(conn, notebook_id)


@router.put("/{notebook_id}")
def update_notebook(notebook_id: int, body: NotebookUpdate, conn: Conn) -> Notebook:
    notebook = repo.update_notebook(conn, notebook_id, body.title, body.cover)
    if notebook is None:
        raise NotFoundError("Cuaderno", notebook_id)
    return notebook


@router.delete("/{notebook_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_notebook(notebook_id: int, conn: Conn) -> Response:
    if not repo.delete_notebook(conn, notebook_id):
        raise NotFoundError("Cuaderno", notebook_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/{notebook_id}/notes")
def list_notes(notebook_id: int, conn: Conn) -> list[NoteSummary]:
    _require_notebook(conn, notebook_id)
    return repo.list_notes(conn, notebook_id)


@router.post("/{notebook_id}/notes", status_code=status.HTTP_201_CREATED)
def create_note(notebook_id: int, body: NoteCreate, conn: Conn) -> Note:
    _require_notebook(conn, notebook_id)
    return repo.create_note(conn, notebook_id, body.title, body.content, body.paper)
