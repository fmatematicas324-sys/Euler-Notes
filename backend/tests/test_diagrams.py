import pytest
from fastapi.testclient import TestClient

from app.services.diagrams import _roots

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def _diagram(client: TestClient, **payload):
    return client.post("/diagram", json=payload)


@pytest.mark.parametrize(
    "payload",
    [
        {"kind": "function", "expr": "x^3 - 3x", "op": "diff", "x_min": -2.5, "x_max": 2.5},
        {"kind": "function", "expr": "x^2 = x + 2", "op": "solve"},
        {"kind": "function", "expr": "x^2 - 4", "op": "solve"},
        {"kind": "function", "expr": "sin(x)", "op": "integrate", "theme": "dark"},
        {"kind": "function", "expr": "exp(-x^2)", "op": "integrate"},  # primitiva con erf
        {"kind": "function", "expr": "sin(x)^2 + cos(x)^2", "op": "simplify"},
        {"kind": "function", "expr": "t^2", "op": "diff", "var": "t", "x_min": -1, "x_max": 1},
        {"kind": "function", "expr": "1/x", "op": "solve"},  # sin raíces: asíntota
        {"kind": "forces", "forces": [{"label": "Peso", "magnitude": 9.8, "angle": 270}]},
        {
            "kind": "forces",
            "forces": [
                {"label": "N", "magnitude": 5, "angle": 90},
                {"label": "P", "magnitude": 5, "angle": 270},
            ],
        },
        {"kind": "projectile", "v0": 20, "angle": 45},
        {"kind": "projectile", "v0": 5, "angle": 90, "h0": 10, "g": 1.62},
        {"kind": "graph", "edges": [{"source": "A", "target": "B"}]},
        {
            "kind": "graph",
            "directed": True,
            "edges": [
                {"source": f"N{i}", "target": f"N{(i * 3) % 9}", "weight": i} for i in range(9)
            ],
        },
    ],
)
def test_diagram_kinds(client: TestClient, payload: dict) -> None:
    response = client.post("/diagram", json=payload)
    assert response.status_code == 200, (payload, response.text)
    assert response.headers["content-type"] == "image/png"
    assert response.content.startswith(PNG_SIGNATURE)


def test_unknown_kind(client: TestClient) -> None:
    response = _diagram(client, kind="circuito")
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"


@pytest.mark.parametrize(
    "payload",
    [
        {"kind": "function", "expr": "x", "op": "factor"},
        {"kind": "function", "expr": "x", "op": "diff", "x_min": 3, "x_max": 1},
        {"kind": "forces", "forces": []},
        {"kind": "forces", "forces": [{"label": "$x$", "magnitude": 1, "angle": 0}]},
        {"kind": "forces", "forces": [{"label": "F", "magnitude": -1, "angle": 0}]},
        {"kind": "projectile", "v0": 10, "angle": 0},
        {"kind": "projectile", "v0": 10, "angle": 95},
        {"kind": "graph", "edges": []},
        {"kind": "graph", "edges": [{"source": "A", "target": "B;C"}]},
    ],
)
def test_invalid_diagrams(client: TestClient, payload: dict) -> None:
    response = client.post("/diagram", json=payload)
    assert response.status_code == 422, payload


@pytest.mark.parametrize("expr", ["__import__('os')", "x.__class__", "a*x"])
def test_function_diagram_rejects_unsafe_or_extra_symbols(client: TestClient, expr: str) -> None:
    response = _diagram(client, kind="function", expr=expr, op="simplify")
    assert response.status_code == 400
    assert response.json()["error"]["code"] == "invalid_expression"


def test_roots_skip_asymptotes() -> None:
    import numpy as np
    import sympy as sp

    x = sp.Symbol("x")
    xs = np.linspace(-5, 5, 1201)
    assert _roots(1 / x, x, xs) == []
    assert _roots(sp.tan(x), x, np.linspace(-1, 1, 1201)) == pytest.approx([0.0], abs=1e-9)
    assert _roots(x**2 - 2, x, xs) == pytest.approx([-(2**0.5), 2**0.5], abs=1e-9)
