"""Punto de entrada del backend de Euler Notes.

Arranque local:
    .venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000

Todas las rutas salvo `/health` y la documentación exigen el token de acceso
(`Authorization: Bearer ...`); ver `app/security.py` y `docs/SERVER_SECURITY.md`.
"""

import logging
import threading
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api import auth, compute, documents, drawings, health, notebooks, notes, plot
from app.config import VERSION, get_db_path
from app.errors import register_error_handlers
from app.security import SecurityMiddleware, TokenStore
from app.services.sandbox import start_worker_pool
from app.storage.db import init_db

# Solo se aceptan peticiones del propio equipo (Flutter Web en localhost).
LOCALHOST_ORIGINS = r"^http://(localhost|127\.0\.0\.1)(:\d+)?$"


logger = logging.getLogger("uvicorn.error")


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    db_path = get_db_path()
    init_db(db_path)
    app.state.db_path = db_path
    tokens: TokenStore = app.state.tokens
    tokens.get()  # crea el token si aún no existe
    logger.info(
        "Euler Notes %s. Token de acceso en %s (cópialo en la app: Servidor → Token).",
        VERSION,
        tokens.source(),
    )
    threading.Thread(target=start_worker_pool, daemon=True).start()
    yield


def create_app() -> FastAPI:
    app = FastAPI(title="Euler Notes API", version=VERSION, lifespan=lifespan)
    app.state.tokens = TokenStore(lambda: get_db_path().parent)
    # Orden: el último middleware añadido es el más externo. CORS va por fuera
    # para que los 401/403 lleven sus cabeceras y el preflight no pida token.
    app.add_middleware(SecurityMiddleware, tokens=app.state.tokens)
    app.add_middleware(
        CORSMiddleware,
        allow_origin_regex=LOCALHOST_ORIGINS,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    register_error_handlers(app)
    for module in (health, auth, notebooks, notes, compute, plot, documents, drawings):
        app.include_router(module.router)
    return app


app = create_app()
