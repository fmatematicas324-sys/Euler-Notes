"""Diagramas científicos para acompañar ejercicios resueltos.

- `function`: análisis visual de la operación de `/compute` (raíces, extremos,
  primitiva, simplificación) sobre la gráfica de la función.
- `forces`: diagrama de cuerpo libre con resultante.
- `projectile`: tiro parabólico con altura máxima, alcance y tiempo de vuelo.
- `graph`: grafo (teoría de grafos, redes, circuitos) dibujado con NetworkX.
- `surface`: superficie z = f(x, y) en 3D con curvas de nivel en la base.
- `contour`: curvas de nivel f(x, y) = c en el plano.
- `vector_field`: campo vectorial F = (P, Q) con flechas o líneas de campo,
  y su divergencia y rotacional calculados con SymPy.
- `curve3d`: curva paramétrica r(t) = (x(t), y(t), z(t)) en el espacio.

Recibe un `dict` ya validado por Pydantic (`DiagramRequest`). Se ejecuta en el
subproceso aislado (`sandbox`).
"""

import math
from typing import Any

import networkx as nx
import numpy as np
import sympy as sp
from matplotlib import colormaps
from matplotlib.backends.backend_agg import FigureCanvasAgg
from matplotlib.cm import ScalarMappable
from matplotlib.colors import Colormap, Normalize
from matplotlib.figure import Figure
from matplotlib.patches import Rectangle
from mpl_toolkits.mplot3d.art3d import Line3DCollection, Poly3DCollection

from app.services import plotting as pl
from app.services import sympy_engine as engine

MAX_MARKERS = 10
SURFACE_SAMPLES = 60  # nodos por eje de la malla 3D (59 × 59 caras)
CONTOUR_SAMPLES = 160  # nodos por eje para las curvas de nivel
ARROW_SAMPLES = 21  # flechas por eje del campo vectorial
STREAM_SAMPLES = 60  # malla para las líneas de campo
CURVE_SAMPLES = 1500  # puntos de la curva paramétrica
CMAP = "viridis"
PAD_3D = 0.14  # separación entre la figura 3D y su barra de color


def validate_diagram(spec: dict[str, Any]) -> None:
    """Validación barata en el proceso principal. Lanza ExpressionError."""
    if spec["kind"] == "function":
        engine.validate(spec["expr"], spec["op"])
    elif spec["kind"] in ("surface", "contour"):
        engine.validate(spec["expr"], "simplify")
    elif spec["kind"] == "vector_field":
        for key in ("p", "q"):
            engine.validate(spec[key], "simplify")
    elif spec["kind"] == "curve3d":
        for key in ("x", "y", "z"):
            engine.validate(spec[key], "simplify")


def render_diagram(spec: dict[str, Any]) -> bytes:
    renderers = {
        "function": _function,
        "forces": _forces,
        "projectile": _projectile,
        "graph": _graph,
        "surface": _surface,
        "contour": _contour,
        "vector_field": _vector_field,
        "curve3d": _curve3d,
    }
    return renderers[spec["kind"]](spec)


def _figure(spec: dict[str, Any]):  # noqa: ANN202
    return pl.new_axes(spec["theme"], spec["width"], spec["height"], spec["scale"])


def _annotate(ax, theme: str, x: float, y: float, text: str, color: str) -> None:  # noqa: ANN001
    ink = pl.INK[theme]
    ax.scatter([x], [y], s=46, color=color, edgecolors=ink["text"], linewidths=0.8, zorder=6)
    ax.annotate(
        text, (x, y), textcoords="offset points", xytext=(7, 9), fontsize=9,
        color=ink["text"], zorder=7,
        bbox={"boxstyle": "round,pad=0.25", "fc": ink["legend"], "ec": ink["grid"], "alpha": 0.9},
    )  # fmt: skip


# --- Análisis de funciones -----------------------------------------------------


def _parse_in(text: str, var: sp.Symbol) -> sp.Expr:
    expr = engine.parse(text)
    extra = sorted(str(s) for s in expr.free_symbols - {var})
    if extra:
        hint = " Para f(x, y) usa «tipo: superficie»." if len(extra) == 1 else ""
        raise engine.ExpressionError(
            f"Para dibujarla, «{text.strip()}» solo puede depender de {var} "
            f"(contiene {', '.join(extra)}).{hint}"
        )
    return expr


def _scalar(expr: sp.Expr, var: sp.Symbol):  # noqa: ANN202
    fn = sp.lambdify(var, expr, modules="mpmath")

    def evaluate(x: float) -> float:
        try:
            value = complex(fn(float(x)))
        except Exception:
            return math.nan
        return value.real if abs(value.imag) <= 1e-9 * max(1.0, abs(value.real)) else math.nan

    return evaluate


def _roots(expr: sp.Expr, var: sp.Symbol, xs: np.ndarray) -> list[float]:
    """Raíces reales en el intervalo: cambios de signo refinados por bisección.
    Se descartan los saltos de signo en asíntotas (p. ej. 1/x en 0)."""
    ys = pl.sample(expr, var, xs)
    evaluate = _scalar(expr, var)
    finite = np.isfinite(ys)
    if not finite.any():
        return []
    tolerance = 1e-6 * max(1.0, float(np.nanmax(np.abs(ys))))
    roots: list[float] = []
    for i in range(len(xs) - 1):
        a, b = ys[i], ys[i + 1]
        if not (finite[i] and finite[i + 1]):
            continue
        if a == 0:
            roots.append(float(xs[i]))
            continue
        if a * b > 0:
            continue
        low, high, f_low = float(xs[i]), float(xs[i + 1]), float(a)
        for _ in range(60):
            mid = (low + high) / 2
            f_mid = evaluate(mid)
            if not math.isfinite(f_mid):
                break
            if (f_mid < 0) == (f_low < 0):
                low, f_low = mid, f_mid
            else:
                high = mid
        root = (low + high) / 2
        value = evaluate(root)
        if math.isfinite(value) and abs(value) <= tolerance:
            roots.append(root)
    unique: list[float] = []
    for root in roots:
        if not unique or abs(root - unique[-1]) > 1e-6 * (xs[-1] - xs[0]):
            unique.append(root)
    return unique


def _fmt(value: float) -> str:
    # Los ceros numéricos (p. ej. -4.5e-21 tras la bisección) se muestran como 0.
    if abs(value) < 1e-9:
        return "0"
    return f"{value:.3g}" if abs(value) >= 1e-3 else f"{value:.2e}"


def _function(spec: dict[str, Any]) -> bytes:
    theme, op, text = spec["theme"], spec["op"], spec["expr"]
    engine.validate(text, op)
    var = sp.Symbol(spec["var"])
    x_range = (spec["x_min"], spec["x_max"])
    xs = np.linspace(*x_range, pl.SAMPLES)
    colors = pl.SERIES[theme]
    v = spec["var"]

    curves: list[tuple[sp.Expr, str, str]] = []  # (expresión, etiqueta, estilo)
    markers: list[tuple[float, float, str]] = []
    fill: sp.Expr | None = None

    if op == "solve" and "=" in text:
        lhs_text, _, rhs_text = text.partition("=")
        lhs, rhs = _parse_in(lhs_text, var), _parse_in(rhs_text, var)
        curves = [(lhs, pl.math_label(lhs), "-"), (rhs, pl.math_label(rhs), "-")]
        evaluate = _scalar(lhs, var)
        markers = [(r, evaluate(r), f"{v} = {_fmt(r)}") for r in _roots(lhs - rhs, var, xs)]
        title = "Solución gráfica: intersecciones"
    else:
        f = _parse_in(text, var)
        curves = [(f, pl.math_label(f, f"f({v}) = "), "-")]
        evaluate = _scalar(f, var)
        if op == "solve":
            markers = [(r, 0.0, f"{v} = {_fmt(r)}") for r in _roots(f, var, xs)]
            title = "Raíces de f"
        elif op == "diff":
            derivative = sp.diff(f, var)
            curves.append((derivative, pl.math_label(derivative, f"f'({v}) = "), "--"))
            slope = _scalar(derivative, var)
            h = (x_range[1] - x_range[0]) * 1e-3
            for r in _roots(derivative, var, xs):
                before, after = slope(r - h), slope(r + h)
                kind = "máx" if before > 0 > after else "mín" if before < 0 < after else "crít."
                markers.append((r, evaluate(r), f"{kind} ({_fmt(r)}, {_fmt(evaluate(r))})"))
            title = "Derivada: puntos críticos de f"
        elif op == "integrate":
            primitive = sp.integrate(f, var)
            if not primitive.has(sp.Integral):
                curves.append((primitive, pl.math_label(primitive, f"F({v}) = "), "--"))
            fill = f
            title = "Integral: f y su primitiva (C = 0)"
        else:
            simplified = sp.simplify(f)
            curves.append((simplified, pl.math_label(simplified, "simplificada: "), "--"))
            title = "Simplificación: ambas curvas coinciden"

    sampled = [pl.sample(expr, var, xs) for expr, _, _ in curves]
    y_range = pl.auto_y_range(sampled)
    fig, ax = _figure(spec)
    pl.style_cartesian(ax, theme, x_range, y_range)
    for (_, label, style), ys, color in zip(curves, sampled, colors, strict=False):
        ax.plot(
            xs, pl.break_discontinuities(ys, *y_range), style, color=color, linewidth=2,
            label=label, zorder=3,
        )  # fmt: skip
    if fill is not None:
        ys = pl.break_discontinuities(sampled[0], *y_range)
        ax.fill_between(xs, 0, ys, where=np.isfinite(ys), color=colors[0], alpha=0.15, zorder=2)
    for x, y, label in markers[:MAX_MARKERS]:
        if math.isfinite(y):
            _annotate(ax, theme, x, y, label, colors[2])
    if len(markers) > MAX_MARKERS:
        title += f" (se muestran {MAX_MARKERS} de {len(markers)})"
    ax.set_title(title, fontsize=11)
    ax.set_xlabel(v)
    return pl.to_png(fig, ax, theme)


# --- Física: cuerpo libre --------------------------------------------------------


def _forces(spec: dict[str, Any]) -> bytes:
    theme = spec["theme"]
    ink, colors = pl.INK[theme], pl.SERIES[theme]
    vectors = []
    for force in spec["forces"]:
        angle = math.radians(force["angle"])
        magnitude = force["magnitude"]
        vectors.append(
            (force["label"], magnitude, magnitude * math.cos(angle), magnitude * math.sin(angle))
        )
    rx, ry = sum(v[2] for v in vectors), sum(v[3] for v in vectors)
    resultant = math.hypot(rx, ry)
    longest = max([v[1] for v in vectors] + [resultant])
    scale = 1.0 / longest

    fig, ax = _figure(spec)
    ax.axhline(0, color=ink["grid"], linewidth=0.8, linestyle=":", zorder=1)
    ax.axvline(0, color=ink["grid"], linewidth=0.8, linestyle=":", zorder=1)
    ax.add_patch(
        Rectangle((-0.11, -0.11), 0.22, 0.22, facecolor=ink["legend"], edgecolor=ink["text"],
                  linewidth=1.5, zorder=4)
    )  # fmt: skip

    def arrow(dx: float, dy: float, color: str, style: str = "-") -> None:
        ax.annotate(
            "", xy=(dx, dy), xytext=(0, 0), zorder=5,
            arrowprops={"arrowstyle": "-|>,head_width=0.35,head_length=0.7", "lw": 2.4,
                        "color": color, "shrinkA": 0, "shrinkB": 0, "linestyle": style},
        )  # fmt: skip

    for index, (label, magnitude, fx, fy) in enumerate(vectors):
        color = colors[index % len(colors)]
        dx, dy = fx * scale, fy * scale
        arrow(dx, dy, color)
        # Etiqueta más allá de la punta, en la dirección de la fuerza.
        norm = math.hypot(dx, dy) or 1.0
        ax.text(
            dx + 0.2 * dx / norm, dy + 0.2 * dy / norm, f"{label}\n{magnitude:g}",
            ha="center", va="center", color=color, fontsize=10, fontweight="bold", zorder=6,
        )  # fmt: skip

    if spec.get("show_resultant", True) and len(vectors) >= 2:
        if resultant * scale < 1e-6:
            summary = "ΣF = 0  (equilibrio)"
        else:
            arrow(rx * scale, ry * scale, ink["text"], "--")
            angle = math.degrees(math.atan2(ry, rx))
            summary = f"Resultante (- -)\nR = {resultant:.3g}  ∠ {angle:.1f}°"
        ax.text(
            0.01, 0.99, summary, transform=ax.transAxes, va="top", color=ink["text"],
            fontsize=10,
            bbox={"boxstyle": "round,pad=0.3", "fc": ink["legend"], "ec": ink["grid"]},
        )  # fmt: skip

    ax.set_xlim(-1.6, 1.6)
    ax.set_ylim(-1.45, 1.45)
    ax.set_aspect("equal")
    ax.set_xticks([])
    ax.set_yticks([])
    for spine in ax.spines.values():
        spine.set_visible(False)
    ax.set_title("Diagrama de cuerpo libre", fontsize=11)
    return pl.to_png(fig, ax, theme, legend=False)


# --- Física: tiro parabólico ---------------------------------------------------


def _projectile(spec: dict[str, Any]) -> bytes:
    theme = spec["theme"]
    ink, colors = pl.INK[theme], pl.SERIES[theme]
    v0, g, h0 = spec["v0"], spec["g"], spec["h0"]
    theta = math.radians(spec["angle"])
    vx, vy = v0 * math.cos(theta), v0 * math.sin(theta)
    flight = (vy + math.sqrt(vy * vy + 2 * g * h0)) / g
    t = np.linspace(0, flight, 400)
    x, y = vx * t, h0 + vy * t - 0.5 * g * t * t
    apex_t = max(vy / g, 0.0)
    apex_x, apex_y = vx * apex_t, h0 + vy * apex_t - 0.5 * g * apex_t**2
    reach = vx * flight

    fig, ax = _figure(spec)
    width = max(reach, 1e-9)
    height = max(apex_y, h0, 1e-9)
    ax.axhline(0, color=ink["axis"], linewidth=1.2, zorder=1)
    ax.plot(x, y, color=colors[0], linewidth=2.4, zorder=3, label="trayectoria")
    ax.plot([apex_x, apex_x], [0, apex_y], ":", color=ink["axis"], linewidth=1.2, zorder=2)
    arrow_len = 0.18 * max(width, height)
    ax.annotate(
        "", xy=(arrow_len * math.cos(theta), h0 + arrow_len * math.sin(theta)), xytext=(0, h0),
        arrowprops={"arrowstyle": "-|>", "lw": 2.2, "color": colors[1]}, zorder=5,
    )  # fmt: skip
    ax.annotate(
        f"v₀ = {v0:g} m/s", (arrow_len * math.cos(theta), h0 + arrow_len * math.sin(theta)),
        textcoords="offset points", xytext=(10, -14), color=colors[1], fontsize=10,
    )  # fmt: skip
    _annotate(ax, theme, apex_x, apex_y, f"h máx = {apex_y:.3g} m", colors[2])
    _annotate(ax, theme, reach, 0.0, f"alcance = {reach:.3g} m", colors[2])
    ax.text(
        0.02, 0.96, f"t vuelo = {flight:.3g} s\ng = {g:g} m/s²", transform=ax.transAxes,
        va="top", fontsize=9, color=ink["text"],
    )  # fmt: skip
    ax.set_xlim(-0.04 * width, width * 1.12)
    ax.set_ylim(-0.06 * height, height * 1.3)
    ax.grid(True, color=ink["grid"], linewidth=0.7)
    ax.set_xlabel("x (m)")
    ax.set_ylabel("y (m)")
    ax.set_title(f"Tiro parabólico: v₀ = {v0:g} m/s, θ = {spec['angle']:g}°", fontsize=11)
    return pl.to_png(fig, ax, theme, legend=False)


# --- Grafos (NetworkX) -----------------------------------------------------------


def _graph(spec: dict[str, Any]) -> bytes:
    theme = spec["theme"]
    ink, colors = pl.INK[theme], pl.SERIES[theme]
    graph = nx.DiGraph() if spec["directed"] else nx.Graph()
    weights = {}
    for edge in spec["edges"]:
        graph.add_edge(edge["source"], edge["target"])
        if edge.get("weight") is not None:
            weights[(edge["source"], edge["target"])] = f"{edge['weight']:g}"
    # Disposición determinista: misma entrada, misma imagen.
    positions = (
        nx.circular_layout(graph) if graph.number_of_nodes() <= 6
        else nx.spring_layout(graph, seed=7)
    )  # fmt: skip

    fig, ax = _figure(spec)
    node_text = "#ffffff" if theme == "light" else "#1b1f24"
    # Flechas solo en grafos dirigidos (en los no dirigidos networkx usa líneas simples).
    arrow_options = (
        {"arrows": True, "arrowsize": 18, "node_size": 900, "connectionstyle": "arc3,rad=0.08"}
        if spec["directed"]
        else {"arrows": False}
    )
    nx.draw_networkx_edges(
        graph, positions, ax=ax, edge_color=ink["axis"], width=2, **arrow_options
    )
    nx.draw_networkx_nodes(
        graph, positions, ax=ax, node_color=colors[0], node_size=900,
        edgecolors=ink["text"], linewidths=1.2,
    )  # fmt: skip
    nx.draw_networkx_labels(graph, positions, ax=ax, font_color=node_text, font_size=11)
    if weights:
        nx.draw_networkx_edge_labels(
            graph, positions, edge_labels=weights, ax=ax, font_color=ink["text"], font_size=9,
            bbox={"boxstyle": "round,pad=0.2", "fc": ink["legend"], "ec": "none", "alpha": 0.9},
        )  # fmt: skip
    ax.margins(0.15)
    ax.axis("off")
    kind = "dirigido" if spec["directed"] else "no dirigido"
    ax.set_title(
        f"Grafo {kind}: {graph.number_of_nodes()} nodos, {graph.number_of_edges()} aristas",
        fontsize=11,
    )
    return pl.to_png(fig, ax, theme, legend=False)


# --- Funciones de dos variables: utilidades comunes -----------------------------


def _parse_only(text: str, allowed: set[sp.Symbol]) -> sp.Expr:
    """Interpreta `text` y comprueba que solo usa las variables permitidas."""
    expr = engine.parse(text)
    extra = sorted(str(s) for s in expr.free_symbols - allowed)
    if extra:
        names = ", ".join(sorted(str(s) for s in allowed))
        raise engine.ExpressionError(
            f"«{text.strip()}» solo puede depender de {names} (contiene {', '.join(extra)})"
        )
    return expr


def _sample_grid(
    expr: sp.Expr, x: sp.Symbol, y: sp.Symbol, xx: np.ndarray, yy: np.ndarray
) -> np.ndarray:
    """Valores reales de `expr` en la malla; NaN donde no hay valor real."""
    fn = sp.lambdify((x, y), expr, modules="numpy")
    with np.errstate(all="ignore"):
        try:
            values = np.broadcast_to(np.asarray(fn(xx, yy), dtype=complex), xx.shape)
        except Exception:
            # Sin versión vectorizada en numpy: punto a punto con mpmath.
            scalar_fn = sp.lambdify((x, y), expr, modules="mpmath")

            def point(a: float, b: float) -> complex:
                try:
                    return complex(scalar_fn(float(a), float(b)))
                except Exception:
                    return complex("nan")

            values = np.vectorize(point, otypes=[complex])(xx, yy)
        real_valued = np.abs(values.imag) <= 1e-9 * np.maximum(1.0, np.abs(values.real))
        zz = np.where(real_valued, values.real, np.nan)
    zz[~np.isfinite(zz)] = np.nan
    return zz


def _region(spec: dict[str, Any], samples: int):  # noqa: ANN202
    """Símbolos y malla de la región del plano de `spec`."""
    x, y = sp.Symbol(spec["var_x"]), sp.Symbol(spec["var_y"])
    xs = np.linspace(spec["x_min"], spec["x_max"], samples)
    ys = np.linspace(spec["y_min"], spec["y_max"], samples)
    xx, yy = np.meshgrid(xs, ys)
    return x, y, xs, ys, xx, yy


def _clip_range(values: np.ndarray) -> tuple[np.ndarray, float, float]:
    """Rango por percentiles (los polos no aplastan la figura): se descartan los
    valores muy lejanos y se recortan los demás al rango."""
    low, high = pl.auto_y_range([values.ravel()])
    span = high - low
    values = values.copy()
    values[(values < low - span) | (values > high + span)] = np.nan
    return np.clip(values, low, high), low, high


def _colorbar(  # noqa: ANN001
    fig: Figure, ax, mappable, theme: str, label: str = "", *, pad: float = 0.04
) -> None:
    """Barra de color. En 3D necesita más separación (`PAD_3D`): si no, se monta
    sobre las marcas del eje z."""
    ink = pl.INK[theme]
    bar = fig.colorbar(mappable, ax=ax, shrink=0.7, pad=pad)
    bar.ax.tick_params(colors=ink["text"], labelsize=8)
    bar.outline.set_edgecolor(ink["grid"])
    if label:
        bar.set_label(label, color=ink["text"])


def _equal_aspect_if_close(ax, spec: dict[str, Any]) -> None:  # noqa: ANN001
    """Escala igual en x e y cuando los rangos son parecidos: así los campos y
    las curvas de nivel no se ven deformados."""
    ratio = (spec["x_max"] - spec["x_min"]) / (spec["y_max"] - spec["y_min"])
    if 1 / 3 <= ratio <= 3:
        ax.set_aspect("equal", adjustable="box")


def _axes_3d(spec: dict[str, Any]):  # noqa: ANN202
    fig = Figure(figsize=(spec["width"] / 100, spec["height"] / 100), dpi=100 * spec["scale"])
    FigureCanvasAgg(fig)
    ax = fig.add_subplot(projection="3d")
    ax.set_facecolor("none")
    return fig, ax


def _style_3d(ax, theme: str, labels: tuple[str, str, str]) -> None:  # noqa: ANN001
    ink = pl.INK[theme]
    ax.set_xlabel(labels[0])
    ax.set_ylabel(labels[1])
    ax.set_zlabel(labels[2])
    for axis in (ax.xaxis, ax.yaxis, ax.zaxis):
        axis.set_pane_color((1.0, 1.0, 1.0, 0.0))
        axis.set_tick_params(colors=ink["text"], labelsize=8)
        axis.label.set_color(ink["text"])


# --- Superficies 3D ----------------------------------------------------------------


def _surface(spec: dict[str, Any]) -> bytes:
    theme, text = spec["theme"], spec["expr"]
    engine.validate(text, "simplify")
    x, y, _, _, xx, yy = _region(spec, SURFACE_SAMPLES)
    expr = _parse_only(text, {x, y})
    zz, z_min, z_max = _clip_range(_sample_grid(expr, x, y, xx, yy))

    # Caras de la malla construidas a mano: se descartan las que tienen algún
    # vértice sin valor real (p. ej. fuera del dominio de sqrt), sin depender de
    # cómo trate cada versión de matplotlib los NaN en `plot_surface`.
    corners = np.stack(
        [
            np.stack([xx[:-1, :-1], yy[:-1, :-1], zz[:-1, :-1]], axis=-1),
            np.stack([xx[:-1, 1:], yy[:-1, 1:], zz[:-1, 1:]], axis=-1),
            np.stack([xx[1:, 1:], yy[1:, 1:], zz[1:, 1:]], axis=-1),
            np.stack([xx[1:, :-1], yy[1:, :-1], zz[1:, :-1]], axis=-1),
        ],
        axis=2,
    ).reshape(-1, 4, 3)
    finite = np.isfinite(corners).all(axis=(1, 2))
    if not finite.any():
        raise engine.ComputeFailure("La función no tiene valores reales en la región indicada")
    faces = corners[finite]
    cmap = colormaps[CMAP]
    norm = Normalize(z_min, z_max)
    ink = pl.INK[theme]

    fig, ax = _axes_3d(spec)
    ax.add_collection3d(
        Poly3DCollection(
            faces, facecolors=cmap(norm(faces[:, :, 2].mean(axis=1))),
            edgecolors=ink["grid"], linewidths=0.15, alpha=0.95,
        )
    )  # fmt: skip
    if spec.get("contours", True):
        ax.contour(
            xx, yy, np.ma.masked_invalid(zz), levels=10, zdir="z", offset=z_min,
            cmap=cmap, norm=norm, linewidths=1,
        )  # fmt: skip
    ax.set_xlim(spec["x_min"], spec["x_max"])
    ax.set_ylim(spec["y_min"], spec["y_max"])
    ax.set_zlim(z_min, z_max)
    _style_3d(ax, theme, (str(x), str(y), "z"))
    _colorbar(fig, ax, ScalarMappable(norm=norm, cmap=cmap), theme, pad=PAD_3D)
    ax.set_title(pl.math_label(expr, "z = "), fontsize=11)
    return pl.to_png(fig, ax, theme, legend=False)


# --- Curvas de nivel -------------------------------------------------------------


def _contour(spec: dict[str, Any]) -> bytes:
    theme, text = spec["theme"], spec["expr"]
    engine.validate(text, "simplify")
    x, y, xs, ys, xx, yy = _region(spec, CONTOUR_SAMPLES)
    expr = _parse_only(text, {x, y})
    zz, z_min, z_max = _clip_range(_sample_grid(expr, x, y, xx, yy))
    if not np.isfinite(zz).any():
        raise engine.ComputeFailure("La función no tiene valores reales en la región indicada")
    ink = pl.INK[theme]
    cmap: Colormap = colormaps[CMAP]
    levels = np.linspace(z_min, z_max, spec["levels"])
    masked = np.ma.masked_invalid(zz)

    fig, ax = pl.new_axes(theme, spec["width"], spec["height"], spec["scale"])
    if spec.get("filled", True):
        filled = ax.contourf(xs, ys, masked, levels=levels, cmap=cmap, alpha=0.9)
        lines = ax.contour(xs, ys, masked, levels=levels, colors=ink["text"], linewidths=0.6)
        mappable = filled
    else:
        lines = ax.contour(xs, ys, masked, levels=levels, cmap=cmap, linewidths=1.6)
        mappable = lines
    if lines.levels.size:
        labels = ax.clabel(lines, inline=True, fontsize=8, fmt="%.3g")
        for label in labels:
            label.set_color(ink["text"])
    ax.set_xlim(spec["x_min"], spec["x_max"])
    ax.set_ylim(spec["y_min"], spec["y_max"])
    ax.grid(True, color=ink["grid"], linewidth=0.5, alpha=0.6)
    _equal_aspect_if_close(ax, spec)
    _colorbar(fig, ax, mappable, theme)
    ax.set_xlabel(str(x))
    ax.set_ylabel(str(y))
    ax.set_title(
        pl.mathtext_or(f"Curvas de nivel de {pl.math_label(expr, 'f = ')}", f"f = {expr}"),
        fontsize=11,
    )
    return pl.to_png(fig, ax, theme, legend=False)


# --- Campos vectoriales ------------------------------------------------------------


def _vector_label(p: sp.Expr, q: sp.Expr, x: sp.Symbol, y: sp.Symbol) -> str:
    """Título con F, su divergencia y la componente z del rotacional."""
    divergence = sp.simplify(sp.diff(p, x) + sp.diff(q, y))
    curl = sp.simplify(sp.diff(q, x) - sp.diff(p, y))
    math = (
        rf"$\vec{{F}} = \left({sp.latex(p)},\ {sp.latex(q)}\right)$"
        "\n"
        rf"$\nabla\cdot\vec{{F}} = {sp.latex(divergence)}$"
        "      "
        rf"$(\nabla\times\vec{{F}})_z = {sp.latex(curl)}$"
    )
    plain = f"F = ({p}, {q})\ndiv F = {divergence}      (rot F)_z = {curl}"
    return pl.mathtext_or(math, plain)


def _vector_field(spec: dict[str, Any]) -> bytes:
    theme = spec["theme"]
    for key in ("p", "q"):
        engine.validate(spec[key], "simplify")
    arrows = spec.get("mode", "arrows") == "arrows"
    x, y, xs, ys, xx, yy = _region(spec, ARROW_SAMPLES if arrows else STREAM_SAMPLES)
    p, q = _parse_only(spec["p"], {x, y}), _parse_only(spec["q"], {x, y})
    u, v = _sample_grid(p, x, y, xx, yy), _sample_grid(q, x, y, xx, yy)
    with np.errstate(all="ignore"):
        magnitude = np.hypot(u, v)
    finite = np.isfinite(magnitude)
    if not finite.any():
        raise engine.ComputeFailure("El campo no tiene valores reales en la región indicada")
    # Color por módulo con el mismo recorte por percentiles que en las superficies.
    _, m_min, m_max = _clip_range(magnitude)
    m_min = max(m_min, 0.0)
    norm = Normalize(m_min, m_max)
    cmap = colormaps[CMAP]
    ink = pl.INK[theme]

    fig, ax = pl.new_axes(theme, spec["width"], spec["height"], spec["scale"])
    pl.style_cartesian(
        ax, theme, (spec["x_min"], spec["x_max"]), (spec["y_min"], spec["y_max"])
    )  # fmt: skip
    if arrows:
        # Flechas de longitud fija (la dirección) y color según el módulo.
        with np.errstate(all="ignore"):
            ux = np.where(magnitude > 0, u / magnitude, np.nan)
            uy = np.where(magnitude > 0, v / magnitude, np.nan)
        cell = min(xs[1] - xs[0], ys[1] - ys[0])
        mappable = ax.quiver(
            xx, yy, np.ma.masked_invalid(ux), np.ma.masked_invalid(uy),
            np.clip(np.nan_to_num(magnitude, nan=m_min), m_min, m_max),
            cmap=cmap, norm=norm, angles="xy", scale_units="xy", scale=1 / (0.8 * cell),
            pivot="mid", width=0.004, zorder=3,
        )  # fmt: skip
    else:
        stream = ax.streamplot(
            xs, ys, np.ma.masked_invalid(u), np.ma.masked_invalid(v),
            color=np.clip(np.nan_to_num(magnitude, nan=m_min), m_min, m_max),
            cmap=cmap, norm=norm, density=1.3, linewidth=1.3, arrowsize=1.2,
        )  # fmt: skip
        mappable = stream.lines
    _equal_aspect_if_close(ax, spec)
    _colorbar(fig, ax, mappable, theme, r"$|\vec{F}|$")
    ax.set_xlabel(str(x))
    ax.set_ylabel(str(y))
    ax.set_title(_vector_label(p, q, x, y), fontsize=10, color=ink["text"])
    return pl.to_png(fig, ax, theme, legend=False)


# --- Curvas paramétricas 3D --------------------------------------------------------


def _curve3d(spec: dict[str, Any]) -> bytes:
    theme = spec["theme"]
    for key in ("x", "y", "z"):
        engine.validate(spec[key], "simplify")
    t = sp.Symbol(spec["var"])
    exprs = [_parse_only(spec[key], {t}) for key in ("x", "y", "z")]
    ts = np.linspace(spec["t_min"], spec["t_max"], CURVE_SAMPLES)
    points = np.stack([pl.sample(expr, t, ts) for expr in exprs], axis=-1)
    segments = np.stack([points[:-1], points[1:]], axis=1)
    keep = np.isfinite(segments).all(axis=(1, 2))
    if not keep.any():
        raise engine.ComputeFailure("La curva no tiene valores reales en el intervalo indicado")
    ink = pl.INK[theme]
    cmap = colormaps[CMAP]
    norm = Normalize(spec["t_min"], spec["t_max"])

    fig, ax = _axes_3d(spec)
    line = Line3DCollection(segments[keep], cmap=cmap, norm=norm, linewidths=2.2)
    line.set_array(((ts[:-1] + ts[1:]) / 2)[keep])
    ax.add_collection3d(line)
    finite = points[np.isfinite(points).all(axis=1)]
    start, end = finite[0], finite[-1]
    ax.scatter(*start, s=40, color=cmap(0.0), edgecolors=ink["text"], depthshade=False)
    ax.scatter(*end, s=40, color=cmap(1.0), edgecolors=ink["text"], depthshade=False)
    for axis_set, low, high in zip(
        (ax.set_xlim, ax.set_ylim, ax.set_zlim), finite.min(axis=0), finite.max(axis=0),
        strict=True,
    ):  # fmt: skip
        pad = 0.05 * (high - low) if high > low else 1.0
        axis_set(low - pad, high + pad)
    _style_3d(ax, theme, ("x", "y", "z"))
    _colorbar(fig, ax, line, theme, str(t), pad=PAD_3D)
    title = (
        rf"$\vec{{r}}({sp.latex(t)}) = \left({sp.latex(exprs[0])},\ "
        rf"{sp.latex(exprs[1])},\ {sp.latex(exprs[2])}\right)$"
    )
    plain = f"r({t}) = ({exprs[0]}, {exprs[1]}, {exprs[2]})"
    ax.set_title(pl.mathtext_or(title, plain), fontsize=11)
    return pl.to_png(fig, ax, theme, legend=False)
