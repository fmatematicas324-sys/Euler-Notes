"""Ejecuta el motor SymPy en un subproceso con límite de tiempo y de memoria.

Se usa `forkserver` con SymPy precargado: cada cálculo nace de un proceso limpio
(sin hilos ni estado del servidor) y arranca rápido. Si se pasa del tiempo, se mata.
"""

import multiprocessing as mp
import resource
from multiprocessing.connection import Connection

from app.errors import AppError
from app.services import sympy_engine as engine

MEMORY_LIMIT_BYTES = 1 << 30  # 1 GiB por cálculo

_CTX = mp.get_context("forkserver")
_CTX.set_forkserver_preload(["app.services.compute"])


def _worker(conn: Connection, expr: str, op: str, var: str) -> None:
    try:
        resource.setrlimit(resource.RLIMIT_AS, (MEMORY_LIMIT_BYTES, MEMORY_LIMIT_BYTES))
    except (ValueError, OSError):
        pass
    try:
        result = engine.evaluate(expr, op, var)
        conn.send(("ok", result.latex, result.text))
    except engine.ExpressionError as exc:
        conn.send(("invalid", str(exc), ""))
    except MemoryError:
        conn.send(("error", "El cálculo superó el límite de memoria", ""))
    except Exception as exc:
        conn.send(("error", f"No se pudo calcular: {type(exc).__name__}", ""))
    finally:
        conn.close()


def run_compute(expr: str, op: str, var: str, timeout: float) -> engine.ComputeResult:
    # Validación barata en el proceso principal: rechaza sin crear subproceso.
    try:
        engine.validate(expr, op)
    except engine.ExpressionError as exc:
        raise AppError(400, "invalid_expression", str(exc)) from exc

    receiver, sender = _CTX.Pipe(duplex=False)
    process = _CTX.Process(target=_worker, args=(sender, expr, op, var), daemon=True)
    process.start()
    sender.close()
    try:
        if not receiver.poll(timeout):
            raise AppError(408, "compute_timeout", f"El cálculo superó el límite de {timeout:g} s")
        try:
            status, first, second = receiver.recv()
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
        raise AppError(400, "invalid_expression", first)
    if status == "error":
        raise AppError(422, "compute_error", first)
    return engine.ComputeResult(latex=first, text=second)
