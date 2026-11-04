"""Gráficas 2D de expresiones con SymPy + matplotlib.

Sin `pyplot`: se usa `Figure` + Agg directamente (sin estado global). Las
expresiones pasan por la misma validación que `/compute` y se evalúan con
`lambdify` sobre numpy. Debe ejecutarse en el subproceso aislado (`sandbox`).
"""

import io
from dataclasses import dataclass

import numpy as np
import sympy as sp
from matplotlib.axes import Axes
from matplotlib.backends.backend_agg import FigureCanvasAgg
from matplotlib.figure import Figure
from matplotlib.mathtext import MathTextParser

from app.services import sympy_engine as engine

MAX_EXPRESSIONS = 5
SAMPLES = 1200

# Colores por serie (validados para contraste sobre fondo claro y oscuro).
_SERIES = {
    "light": ("#1c64d9", "#d9480f", "#2b8a3e", "#9c36b5", "#c2255c"),
    "dark": ("#74a7ff", "#ff922b", "#69db7c", "#da77f2", "#f783ac"),
}
_INK = {
    "light": {"text": "#343a40", "axis": "#868e96", "grid": "#dee2e6", "legend": "#ffffff"},
    "dark": {"text": "#dee2e6", "axis": "#868e96", "grid": "#3a3f45", "legend": "#25292e"},
}


@dataclass(frozen=True)
class PlotSpec:
    exprs: tuple[str, ...]
    var: str = "x"
    x_min: float = -10.0
    x_max: float = 10.0
    y_min: float | None = None
    y_max: float | None = None
    theme: str = "light"
    width: int = 800
    height: int = 500
    scale: float = 1.0


def validate_spec(spec: PlotSpec) -> None:
    """Validación barata (sin interpretar). Lanza ExpressionError."""
    if not 1 <= len(spec.exprs) <= MAX_EXPRESSIONS:
        raise engine.ExpressionError(f"Indica entre 1 y {MAX_EXPRESSIONS} expresiones")
    for expr in spec.exprs:
        engine.validate(expr, "simplify")


def _prepare(spec: PlotSpec) -> list[sp.Expr]:
    symbol = sp.Symbol(spec.var)
    prepared = []
    for text in spec.exprs:
        expr = engine.parse(text)
        extra = sorted(str(s) for s in expr.free_symbols - {symbol})
        if extra:
            raise engine.ExpressionError(
                f"«{text}» solo puede depender de {spec.var} (contiene {', '.join(extra)})"
            )
        prepared.append(expr)
    return prepared


def _safe_point(fn, x: float) -> complex:  # noqa: ANN001
    try:
        return complex(fn(float(x)))
    except Exception:
        return complex("nan")


def _sample(expr: sp.Expr, symbol: sp.Symbol, xs: np.ndarray) -> np.ndarray:
    """Valores reales de `expr` en `xs`; NaN donde no hay valor real."""
    fn = sp.lambdify(symbol, expr, modules="numpy")
    with np.errstate(all="ignore"):
        try:
            values = np.broadcast_to(np.asarray(fn(xs), dtype=complex), xs.shape)
        except Exception:
            # Sin versión vectorizada en numpy (p. ej. factorial): punto a punto
            # con mpmath (dependencia de SymPy), que cubre todas las funciones.
            scalar_fn = sp.lambdify(symbol, expr, modules="mpmath")
            values = np.array([_safe_point(scalar_fn, x) for x in xs], dtype=complex)
        real_valued = np.abs(values.imag) <= 1e-9 * np.maximum(1.0, np.abs(values.real))
        ys = np.where(real_valued, values.real, np.nan)
    ys[~np.isfinite(ys)] = np.nan
    return ys


def _auto_y_range(curves: list[np.ndarray]) -> tuple[float, float]:
    finite = np.concatenate([c[np.isfinite(c)] for c in curves])
    if finite.size == 0:
        raise engine.ComputeFailure("Ninguna expresión tiene valores reales en el intervalo")
    # Percentiles: las asíntotas (tan, 1/x) no aplastan el resto de la gráfica.
    low, high = (float(v) for v in np.percentile(finite, [2, 98]))
    if high - low < 1e-9:
        low, high = low - 1.0, high + 1.0
    pad = 0.08 * (high - low)
    return low - pad, high + pad


def _break_discontinuities(ys: np.ndarray, y_min: float, y_max: float) -> np.ndarray:
    """Corta la línea en asíntotas para no dibujar trazos verticales falsos."""
    span = y_max - y_min
    ys = ys.copy()
    ys[(ys < y_min - span) | (ys > y_max + span)] = np.nan
    with np.errstate(invalid="ignore"):
        jumps = np.abs(np.diff(ys)) > span
    ys[1:][jumps] = np.nan
    return ys


# --- Utilidades compartidas con `diagrams` -------------------------------------

SERIES = _SERIES
INK = _INK
sample = _sample
auto_y_range = _auto_y_range
break_discontinuities = _break_discontinuities
_MATHTEXT = MathTextParser("path")


def math_label(expr: sp.Expr, prefix: str = "") -> str:
    """Etiqueta mathtext (`$...$`) de una expresión, o texto plano si matplotlib
    no puede interpretar el LaTeX que genera SymPy."""
    # \dfrac: en leyendas, las fracciones de \frac quedan demasiado pequeñas.
    label = f"${prefix}{sp.latex(expr).replace(r'\frac', r'\dfrac')}$"
    try:
        _MATHTEXT.parse(label)
        return label
    except ValueError:
        return f"{prefix}{expr}"


def new_axes(theme: str, width: int, height: int, scale: float) -> tuple[Figure, Axes]:
    fig = Figure(figsize=(width / 100, height / 100), dpi=100 * scale)
    FigureCanvasAgg(fig)
    ax = fig.add_subplot()
    ax.set_facecolor("none")
    ink = _INK[theme]
    ax.tick_params(colors=ink["text"], labelsize=9)
    for spine in ax.spines.values():
        spine.set_color(ink["grid"])
    return fig, ax


def style_cartesian(
    ax: Axes, theme: str, x_range: tuple[float, float], y_range: tuple[float, float]
) -> None:
    """Rejilla, ejes x=0 / y=0 visibles y límites."""
    ink = _INK[theme]
    (x_min, x_max), (y_min, y_max) = x_range, y_range
    if y_min < 0 < y_max:
        ax.axhline(0, color=ink["axis"], linewidth=0.9, zorder=1)
    if x_min < 0 < x_max:
        ax.axvline(0, color=ink["axis"], linewidth=0.9, zorder=1)
    ax.set_xlim(x_min, x_max)
    ax.set_ylim(y_min, y_max)
    ax.grid(True, color=ink["grid"], linewidth=0.7)


def to_png(fig: Figure, ax: Axes, theme: str, *, legend: bool = True) -> bytes:
    ink = _INK[theme]
    if legend and ax.get_legend_handles_labels()[0]:
        box = ax.legend(
            loc="best", fontsize=10, facecolor=ink["legend"], edgecolor=ink["grid"],
            framealpha=0.9,
        )  # fmt: skip
        for text in box.get_texts():
            text.set_color(ink["text"])
    if ax.get_title():
        ax.title.set_color(ink["text"])
    ax.xaxis.label.set_color(ink["text"])
    ax.yaxis.label.set_color(ink["text"])
    fig.tight_layout()
    buffer = io.BytesIO()
    fig.savefig(buffer, format="png", transparent=True)
    return buffer.getvalue()


def render_plot(spec: PlotSpec) -> bytes:
    """PNG (fondo transparente) con las curvas de `spec`. Puede tardar."""
    validate_spec(spec)
    exprs = _prepare(spec)
    symbol = sp.Symbol(spec.var)
    xs = np.linspace(spec.x_min, spec.x_max, SAMPLES)
    curves = [_sample(expr, symbol, xs) for expr in exprs]
    if spec.y_min is not None and spec.y_max is not None:
        y_range = (spec.y_min, spec.y_max)
    else:
        y_range = _auto_y_range(curves)

    fig, ax = new_axes(spec.theme, spec.width, spec.height, spec.scale)
    style_cartesian(ax, spec.theme, (spec.x_min, spec.x_max), y_range)
    for expr, ys, color in zip(exprs, curves, _SERIES[spec.theme], strict=False):
        ax.plot(
            xs, _break_discontinuities(ys, *y_range), color=color, linewidth=2,
            label=math_label(expr), zorder=3,
        )  # fmt: skip
    ax.set_xlabel(spec.var)
    return to_png(fig, ax, spec.theme)


def warm_up() -> None:
    """Carga fuentes y mathtext de matplotlib (≈1 s la primera vez). Se llama al
    precargar el forkserver para que cada gráfica no pague ese coste."""
    render_plot(PlotSpec(exprs=("x",), width=200, height=150))
    from app.services.diagrams import render_diagram  # noqa: PLC0415  (evita ciclo)

    render_diagram(
        {"kind": "graph", "edges": [{"source": "A", "target": "B", "weight": None}],
         "directed": True, "theme": "light", "width": 200, "height": 150, "scale": 1.0}
    )  # fmt: skip
