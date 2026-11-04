"""Biblioteca de PDF: importar, listar, descargar, extraer texto por página."""

import re
import sqlite3
from pathlib import Path
from typing import Annotated

from fastapi import APIRouter, Depends, Query, Request, Response, status
from fastapi.responses import FileResponse
from starlette.concurrency import run_in_threadpool

from app.config import get_pdf_timeout
from app.domain.models import Document, DocumentPageText
from app.errors import AppError, NotFoundError
from app.services import pdf
from app.services.sandbox import run_isolated
from app.storage import repository as repo
from app.storage.db import documents_dir, get_conn

router = APIRouter(prefix="/documents", tags=["documents"])
Conn = Annotated[sqlite3.Connection, Depends(get_conn)]

MAX_PDF_BYTES = 30 * 1024 * 1024


def _file_path(request: Request, document_id: int) -> Path:
    return documents_dir(request.app.state.db_path) / f"{document_id}.pdf"


def _safe_filename(raw: str) -> str:
    name = Path(raw.replace("\\", "/")).name
    name = re.sub(r"[\x00-\x1f]", "", name).strip() or "documento.pdf"
    return name[:200]


def _run_pdf(fn, *args):  # noqa: ANN001, ANN202
    """Ejecuta pypdf aislado y traduce los errores a `invalid_pdf`."""
    try:
        return run_isolated(fn, *args, timeout=get_pdf_timeout())
    except AppError as exc:
        if exc.code == "compute_error":
            raise AppError(422, "invalid_pdf", exc.message) from exc
        raise


def _require(conn: sqlite3.Connection, document_id: int) -> Document:
    document = repo.get_document(conn, document_id)
    if document is None:
        raise NotFoundError("Documento", document_id)
    return document


@router.get("")
def list_documents(conn: Conn) -> list[Document]:
    return repo.list_documents(conn)


@router.post(
    "",
    status_code=status.HTTP_201_CREATED,
    openapi_extra={"requestBody": {"content": {"application/pdf": {"schema": {"type": "string"}}}}},
)
async def upload_document(
    request: Request,
    conn: Conn,
    filename: Annotated[str, Query(min_length=1, max_length=255)] = "documento.pdf",
) -> Document:
    """Cuerpo: el PDF en bruto (`Content-Type: application/pdf`)."""
    data = bytearray()
    async for chunk in request.stream():
        data.extend(chunk)
        if len(data) > MAX_PDF_BYTES:
            raise AppError(413, "file_too_large", "El PDF supera el máximo de 30 MB")
    if not data.startswith(b"%PDF-"):
        raise AppError(400, "invalid_pdf", "El archivo no es un PDF")

    folder = documents_dir(request.app.state.db_path)
    temporary = folder / f"subida-{id(data)}.tmp"
    temporary.write_bytes(data)
    try:
        pages = await run_in_threadpool(_run_pdf, pdf.count_pages, str(temporary))
        document = repo.create_document(conn, _safe_filename(filename), len(data), pages)
        temporary.replace(_file_path(request, document.id))
    finally:
        temporary.unlink(missing_ok=True)
    return document


@router.get("/{document_id}")
def get_document(document_id: int, conn: Conn) -> Document:
    return _require(conn, document_id)


@router.get("/{document_id}/file", response_class=FileResponse)
def download_document(document_id: int, request: Request, conn: Conn) -> FileResponse:
    document = _require(conn, document_id)
    return FileResponse(
        _file_path(request, document_id),
        media_type="application/pdf",
        filename=document.filename,
        content_disposition_type="inline",
    )


@router.get("/{document_id}/pages/{page}/text")
def page_text(document_id: int, page: int, request: Request, conn: Conn) -> DocumentPageText:
    document = _require(conn, document_id)
    if not 1 <= page <= document.pages:
        raise AppError(404, "not_found", f"La página {page} no existe (hay {document.pages})")
    text, latex = _run_pdf(pdf.extract_page, str(_file_path(request, document_id)), page)
    return DocumentPageText(page=page, text=text, latex=latex)


@router.delete("/{document_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_document(document_id: int, request: Request, conn: Conn) -> Response:
    _require(conn, document_id)
    repo.delete_document(conn, document_id)
    _file_path(request, document_id).unlink(missing_ok=True)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
