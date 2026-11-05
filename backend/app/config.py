"""Configuración del backend leída de variables de entorno.

Las variables usan el prefijo `EULER_`. Por compatibilidad se aceptan también los
nombres antiguos `CUADERNO_` (si están las dos, gana `EULER_`).
"""

import os
import tomllib
from importlib import metadata
from pathlib import Path

_BACKEND_DIR = Path(__file__).resolve().parent.parent
# El nombre del archivo se mantiene: cambiarlo dejaría "vacías" las instalaciones existentes.
_DEFAULT_DB_PATH = _BACKEND_DIR / "data" / "cuaderno.db"
_PACKAGE = "euler-notes-backend"


def _read_version() -> str:
    """Versión del producto. Fuente única: `app/pubspec.yaml`, copiada en
    `backend/pyproject.toml` (lo comprueba `tool/check_versions.py` en CI)."""
    try:
        with (_BACKEND_DIR / "pyproject.toml").open("rb") as file:
            return tomllib.load(file)["project"]["version"]
    except (OSError, KeyError, tomllib.TOMLDecodeError):
        pass
    try:
        return metadata.version(_PACKAGE)
    except metadata.PackageNotFoundError:
        return "0.0.0+desconocida"


VERSION = _read_version()


def env(name: str, default: str | None = None) -> str | None:
    """Lee `EULER_<name>` o, si no existe, el nombre antiguo `CUADERNO_<name>`."""
    for prefix in ("EULER_", "CUADERNO_"):
        value = os.environ.get(prefix + name)
        if value is not None:
            return value
    return default


def get_db_path() -> Path:
    """Ruta del archivo SQLite (`EULER_DB_PATH` o `backend/data/cuaderno.db`)."""
    return Path(env("DB_PATH") or _DEFAULT_DB_PATH)


def get_compute_timeout() -> float:
    """Segundos máximos por cálculo simbólico (`EULER_COMPUTE_TIMEOUT`, por defecto 5)."""
    return float(env("COMPUTE_TIMEOUT", "5"))


def get_pdf_timeout() -> float:
    """Segundos máximos para analizar un PDF (`EULER_PDF_TIMEOUT`, por defecto 20)."""
    return float(env("PDF_TIMEOUT", "20"))
