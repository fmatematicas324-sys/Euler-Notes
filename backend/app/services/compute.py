"""Punto de entrada de los cálculos: validación barata en el proceso principal y
ejecución en el subproceso aislado (`sandbox`).

Este módulo se precarga en el forkserver, así que importa todo lo que necesitan
las tareas (SymPy, numpy, matplotlib).
"""

from app.errors import AppError
from app.services import plotting
from app.services import sympy_engine as engine
from app.services.sandbox import run_isolated


def _validated(check, *args) -> None:  # noqa: ANN001
    try:
        check(*args)
    except engine.ExpressionError as exc:
        raise AppError(400, "invalid_expression", str(exc)) from exc


def run_compute(expr: str, op: str, var: str, timeout: float) -> engine.ComputeResult:
    _validated(engine.validate, expr, op)
    return run_isolated(engine.evaluate, expr, op, var, timeout=timeout)


def run_plot(spec: plotting.PlotSpec, timeout: float) -> bytes:
    _validated(plotting.validate_spec, spec)
    return run_isolated(plotting.render_plot, spec, timeout=timeout)
