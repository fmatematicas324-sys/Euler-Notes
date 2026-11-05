"""Ejecución aislada de cálculos (SymPy, matplotlib) con límite de tiempo y memoria.

Se usa `forkserver` con los módulos de cálculo precargados: cada tarea nace de un
proceso limpio (sin los hilos ni el estado del servidor) y arranca rápido. Si se
pasa del tiempo, se mata.
"""

import multiprocessing as mp
import os
import resource
import threading
from collections.abc import Callable
from multiprocessing.connection import Connection
from typing import Any

from app.config import env
from app.errors import AppError
from app.services.sympy_engine import ComputeFailure, ExpressionError

MEMORY_LIMIT_BYTES = 1 << 30  # 1 GiB por tarea

# Tareas aisladas simultáneas (cálculo, gráficas, PDF). Sin límite, cada petición
# crearía un proceso de hasta 1 GiB. `EULER_MAX_PARALLEL_TASKS` (por defecto 2).
MAX_PARALLEL_TASKS = max(1, int(env("MAX_PARALLEL_TASKS", "2") or "2"))
# Segundos que una petición espera un hueco antes de responder 503.
QUEUE_TIMEOUT = float(env("TASK_QUEUE_TIMEOUT", "2") or "2")
_slots = threading.BoundedSemaphore(MAX_PARALLEL_TASKS)

# Antes de arrancar el forkserver: sin hilos de BLAS (memoria virtual enorme con
# RLIMIT_AS) y matplotlib sin interfaz gráfica.
os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")
os.environ.setdefault("OMP_NUM_THREADS", "1")
os.environ.setdefault("MPLBACKEND", "Agg")

_CTX = mp.get_context("forkserver")
# "__main__": el forkserver importa una vez el script principal (uvicorn, pytest...)
# y los subprocesos no lo vuelven a ejecutar en cada tarea.
_CTX.set_forkserver_preload(["__main__", "app.services.preload"])


def _worker(conn: Connection, fn: Callable[..., Any], args: tuple[Any, ...]) -> None:
    try:
        resource.setrlimit(resource.RLIMIT_AS, (MEMORY_LIMIT_BYTES, MEMORY_LIMIT_BYTES))
    except (ValueError, OSError):
        pass
    try:
        conn.send(("ok", fn(*args)))
    except ExpressionError as exc:
        conn.send(("invalid", str(exc)))
    except ComputeFailure as exc:
        conn.send(("error", str(exc)))
    except MemoryError:
        conn.send(("error", "El cálculo superó el límite de memoria"))
    except Exception as exc:
        conn.send(("error", f"No se pudo calcular: {type(exc).__name__}"))
    finally:
        conn.close()


def run_isolated(fn: Callable[..., Any], *args: Any, timeout: float) -> Any:
    """Ejecuta `fn(*args)` en un subproceso. `fn` debe ser una función de módulo.

    Como mucho `MAX_PARALLEL_TASKS` a la vez; si no hay hueco en `QUEUE_TIMEOUT`
    segundos responde 503 (`server_busy`) en lugar de acumular procesos."""
    if not _slots.acquire(timeout=QUEUE_TIMEOUT):
        raise AppError(
            503, "server_busy", "El servidor está ocupado con otros cálculos; inténtalo de nuevo"
        )
    try:
        return _run(fn, *args, timeout=timeout)
    finally:
        _slots.release()


def _run(fn: Callable[..., Any], *args: Any, timeout: float) -> Any:
    receiver, sender = _CTX.Pipe(duplex=False)
    process = _CTX.Process(target=_worker, args=(sender, fn, args), daemon=True)
    process.start()
    sender.close()
    try:
        if not receiver.poll(timeout):
            raise AppError(408, "compute_timeout", f"El cálculo superó el límite de {timeout:g} s")
        try:
            status, payload = receiver.recv()
        except EOFError as exc:
            raise AppError(
                422, "compute_error", "El proceso de cálculo terminó inesperadamente"
            ) from exc
    finally:
        receiver.close()
        if process.is_alive():
            process.kill()
        process.join(timeout=1)

    if status == "invalid":
        raise AppError(400, "invalid_expression", payload)
    if status == "error":
        raise AppError(422, "compute_error", payload)
    return payload


def _noop() -> None:
    return None


def start_worker_pool() -> None:
    """Arranca el forkserver (precarga SymPy y matplotlib, unos segundos) para que
    la primera petición del usuario no espere. Pensado para un hilo en segundo plano."""
    try:
        _run(_noop, timeout=120)  # sin ocupar un hueco de usuario
    except AppError:
        pass
