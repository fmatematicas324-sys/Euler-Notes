"""Punto de entrada del backend de Cuaderno Científico.

Arranque local:
    .venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000
"""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api import health
from app.config import VERSION
from app.errors import register_error_handlers

# Solo se aceptan peticiones del propio equipo (Flutter Web en localhost).
LOCALHOST_ORIGINS = r"^http://(localhost|127\.0\.0\.1)(:\d+)?$"


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
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
    app.include_router(health.router)
    return app


app = create_app()
