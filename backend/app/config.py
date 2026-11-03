"""Configuración del backend leída de variables de entorno."""

import os
from pathlib import Path

VERSION = "0.1.0"

_BACKEND_DIR = Path(__file__).resolve().parent.parent
_DEFAULT_DB_PATH = _BACKEND_DIR / "data" / "cuaderno.db"


def get_db_path() -> Path:
    """Ruta del archivo SQLite (`CUADERNO_DB_PATH` o `backend/data/cuaderno.db`)."""
    return Path(os.environ.get("CUADERNO_DB_PATH", _DEFAULT_DB_PATH))


def get_compute_timeout() -> float:
    """Segundos máximos por cálculo simbólico (`CUADERNO_COMPUTE_TIMEOUT`, por defecto 5)."""
    return float(os.environ.get("CUADERNO_COMPUTE_TIMEOUT", "5"))
