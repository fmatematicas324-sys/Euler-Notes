import struct
import time

import pytest
from fastapi.testclient import TestClient

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def _png_size(data: bytes) -> tuple[int, int]:
    """Ancho y alto en píxeles leídos de la cabecera IHDR."""
    return struct.unpack(">II", data[16:24])


def _plot(client: TestClient, **payload):
    return client.post("/plot", json=payload)


def test_returns_png_with_requested_size(client: TestClient) -> None:
    response = _plot(client, exprs=["sin(x)"])
    assert response.status_code == 200, response.text
    assert response.headers["content-type"] == "image/png"
    assert response.content.startswith(PNG_SIGNATURE)
    assert _png_size(response.content) == (800, 500)


def test_scale_multiplies_pixels(client: TestClient) -> None:
    response = _plot(client, exprs=["x^2"], width=400, height=300, scale=2)
    assert _png_size(response.content) == (800, 600)


@pytest.mark.parametrize(
    "payload",
    [
        {"exprs": ["sin(x)", "cos(x)", "x/5"]},
        {"exprs": ["tan(x)"]},
        {"exprs": ["1/x"]},
        {"exprs": ["sqrt(x)", "ln(x)"]},
        {"exprs": ["3"]},
        {"exprs": ["t^2 - 1"], "var": "t", "x_min": -2, "x_max": 2},
        {"exprs": ["exp(x)"], "y_min": 0, "y_max": 5},
        {"exprs": ["sin(x)"], "theme": "dark"},
        {"exprs": ["factorial(x)"], "x_min": 0, "x_max": 5},
        {"exprs": ["Abs(x) + floor(x)"]},
        {"exprs": ["2x^3 - 3x"], "x_min": -2.5, "x_max": 2.5},
    ],
)
def test_plot_variants(client: TestClient, payload: dict) -> None:
    response = client.post("/plot", json=payload)
    assert response.status_code == 200, (payload, response.text)
    assert response.content.startswith(PNG_SIGNATURE)


def test_extra_symbols_rejected(client: TestClient) -> None:
    response = _plot(client, exprs=["a*x + b"])
    assert response.status_code == 400
    body = response.json()["error"]
    assert body["code"] == "invalid_expression"
    assert "a, b" in body["message"]


@pytest.mark.parametrize("expr", ["__import__('os')", "x.__class__", "x = 1", "lambda: 1"])
def test_unsafe_or_invalid_expressions_rejected(client: TestClient, expr: str) -> None:
    response = _plot(client, exprs=["x", expr])
    assert response.status_code == 400
    assert response.json()["error"]["code"] == "invalid_expression"


def test_no_real_values(client: TestClient) -> None:
    response = _plot(client, exprs=["sqrt(-1 - x^2)"])
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "compute_error"
    assert "valores reales" in response.json()["error"]["message"]


@pytest.mark.parametrize(
    "payload",
    [
        {"exprs": []},
        {"exprs": ["x"] * 6},
        {"exprs": ["x"], "x_min": 5, "x_max": 1},
        {"exprs": ["x"], "y_min": 0},
        {"exprs": ["x"], "y_min": 2, "y_max": 1},
        {"exprs": ["x"], "x_max": 1e9},
        {"exprs": ["x"], "width": 10},
        {"exprs": ["x"], "scale": 5},
        {"exprs": ["x"], "theme": "sepia"},
        {"exprs": ["x"], "var": "_x"},
    ],
)
def test_invalid_requests(client: TestClient, payload: dict) -> None:
    response = client.post("/plot", json=payload)
    assert response.status_code == 422, payload
    assert response.json()["error"]["code"] == "validation_error"


def test_range_error_message_is_clean(client: TestClient) -> None:
    response = _plot(client, exprs=["x"], x_min=5, x_max=1)
    assert response.json()["error"]["message"] == "x_min debe ser menor que x_max"


def test_timeout(client: TestClient, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("CUADERNO_COMPUTE_TIMEOUT", "1")
    start = time.monotonic()
    response = _plot(client, exprs=["9^9^9 * x"])
    assert response.status_code == 408
    assert time.monotonic() - start < 3
