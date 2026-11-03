import time

import pytest
from fastapi.testclient import TestClient

from app.services import sympy_engine as engine


def _compute(client: TestClient, expr: str, op: str, **extra: str):
    return client.post("/compute", json={"expr": expr, "op": op, **extra})


# --- Resultados correctos ----------------------------------------------------


@pytest.mark.parametrize(
    ("expr", "op", "var", "text"),
    [
        ("sin(x)^2 + cos(x)^2", "simplify", "x", "1"),
        ("2x + 3x", "simplify", "x", "5*x"),
        ("sin(x)*x", "diff", "x", "x*cos(x) + sin(x)"),
        ("t^3", "diff", "t", "3*t**2"),
        ("x^2", "integrate", "x", "x**3/3"),
        ("x^2 = 4", "solve", "x", "[-2, 2]"),
        ("x^2 - 9", "solve", "x", "[-3, 3]"),
        ("ln(E)", "simplify", "x", "1"),
        ("2.5*x + 0.5*x", "simplify", "x", "3.0*x"),
    ],
)
def test_compute_results(client: TestClient, expr: str, op: str, var: str, text: str) -> None:
    response = _compute(client, expr, op, var=var)
    assert response.status_code == 200, response.json()
    assert response.json()["result_text"] == text


def test_acceptance_diff_latex(client: TestClient) -> None:
    """Criterio de aceptación 3 de PRODUCT_SPEC.md."""
    body = _compute(client, "sin(x)*x", "diff").json()
    assert body["result_latex"] == r"x \cos{\left(x \right)} + \sin{\left(x \right)}"


def test_integrate_latex(client: TestClient) -> None:
    assert _compute(client, "x^2", "integrate").json()["result_latex"] == r"\frac{x^{3}}{3}"


def test_unknown_names_are_inert_symbols(client: TestClient) -> None:
    """Nombres como eval/system son símbolos inertes (eval(x) se lee como eval·x)."""
    body = _compute(client, "eval(x) + system(y)", "simplify").json()
    assert body["result_text"] == "eval*x + system*y"


# --- Seguridad ---------------------------------------------------------------


@pytest.mark.parametrize(
    "expr",
    [
        "__import__('os').system('ls')",
        "().__class__.__bases__",
        "x.__class__",
        "Symbol.mro",
        "lambda: 1",
        "import os",
        "x if x else y",
        "[x for x in y]",
        "x; y",
        'open("/etc/passwd")',
        "x @ y",
        "{x: 1}",
        "None",
        "a" * 30,
    ],
)
def test_malicious_expressions_rejected(client: TestClient, expr: str) -> None:
    response = _compute(client, expr, "simplify")
    assert response.status_code == 400, expr
    assert response.json()["error"]["code"] == "invalid_expression"


def test_equals_only_allowed_in_solve(client: TestClient) -> None:
    response = _compute(client, "x = 1", "simplify")
    assert response.status_code == 400
    assert _compute(client, "x = 1 = 2", "solve").status_code == 400


@pytest.mark.parametrize("expr", ["2 +* ", "sin(", "(x", "1, 2"])
def test_syntax_errors(client: TestClient, expr: str) -> None:
    response = _compute(client, expr, "simplify")
    assert response.status_code == 400, expr
    assert response.json()["error"]["code"] == "invalid_expression"


def test_timeout_kills_slow_computation(
    client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("CUADERNO_COMPUTE_TIMEOUT", "1")
    start = time.monotonic()
    response = _compute(client, "9^9^9", "simplify")
    elapsed = time.monotonic() - start

    assert response.status_code == 408
    assert response.json()["error"]["code"] == "compute_timeout"
    assert elapsed < 3


# --- Validación de la petición -----------------------------------------------


@pytest.mark.parametrize(
    "payload",
    [
        {"expr": "", "op": "simplify"},
        {"expr": "x", "op": "factor"},
        {"expr": "x", "op": "diff", "var": "x y"},
        {"expr": "x", "op": "diff", "var": "_x"},
        {"expr": "x" * 501, "op": "simplify"},
    ],
)
def test_invalid_requests(client: TestClient, payload: dict) -> None:
    response = client.post("/compute", json=payload)
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"


def test_engine_validate_is_pure() -> None:
    engine.validate("sin(x) + 2.5", "simplify")
    with pytest.raises(engine.ExpressionError):
        engine.validate("x.y", "simplify")
