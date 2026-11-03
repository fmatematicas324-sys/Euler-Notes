"""Punto de entrada del backend de Cuaderno Científico.

Arranque local:
    .venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000
"""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api import health, notebooks, notes
from app.config import VERSION, get_db_path
from app.errors import register_error_handlers
from app.storage.db import init_db

# Solo se aceptan peticiones del propio equipo (Flutter Web en localhost).
LOCALHOST_ORIGINS = r"^http://(localhost|127\.0\.0\.1)(:\d+)?$"


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    db_path = get_db_path()
    init_db(db_path)
    app.state.db_path = db_path
    yield


def create_app() -> FastAPI:
    app = FastAPI(title="Cuaderno Científico API", version=VERSION, lifespan=lifespan)
    app.add_middleware(
        CORSMiddleware,
        allow_origin_regex=LOCALHOST_ORIGINS,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    register_error_handlers(app)
    for module in (health, notebooks, notes):
        app.include_router(module.router)
    return app


app = create_app()
