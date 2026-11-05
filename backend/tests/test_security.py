import os
import stat
import threading
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app import security
from app.services import sandbox
from tests.conftest import LOCAL_CLIENT, TEST_TOKEN, make_client


@pytest.fixture
def anonymous(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> TestClient:
    """Cliente desde el propio equipo, sin token."""
    monkeypatch.setenv("CUADERNO_DB_PATH", str(tmp_path / "test.db"))
    with make_client(headers={}) as test_client:
        yield test_client


def _client_from(host: str, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> TestClient:
    monkeypatch.setenv("CUADERNO_DB_PATH", str(tmp_path / "test.db"))
    return make_client(client=(host, 50000))


# --- Token ---------------------------------------------------------------


def test_local_requests_also_need_token(anonymous: TestClient) -> None:
    response = anonymous.get("/notebooks")
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthorized"
    assert response.headers["www-authenticate"] == "Bearer"


@pytest.mark.parametrize(
    "header",
    [f"Bearer {TEST_TOKEN}x", "Bearer ", f"Basic {TEST_TOKEN}", TEST_TOKEN],
)
def test_wrong_credentials_are_rejected(anonymous: TestClient, header: str) -> None:
    response = anonymous.get("/notebooks", headers={"Authorization": header})
    assert response.status_code == 401


def test_valid_token_is_accepted(client: TestClient) -> None:
    assert client.get("/notebooks").status_code == 200
    assert client.get("/auth/check").json() == {"authenticated": True}


def test_bearer_scheme_is_case_insensitive(anonymous: TestClient) -> None:
    response = anonymous.get("/notebooks", headers={"Authorization": f"bearer {TEST_TOKEN}"})
    assert response.status_code == 200


def test_health_is_public_and_minimal(anonymous: TestClient) -> None:
    response = anonymous.get("/health")
    assert response.status_code == 200
    assert set(response.json()) == {"status", "version"}


def test_auth_check_needs_token(anonymous: TestClient) -> None:
    assert anonymous.get("/auth/check").status_code == 401


def test_cors_preflight_works_without_token(anonymous: TestClient) -> None:
    response = anonymous.options(
        "/notebooks",
        headers={
            "Origin": "http://localhost:5173",
            "Access-Control-Request-Method": "GET",
            "Access-Control-Request-Headers": "authorization",
        },
    )
    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == "http://localhost:5173"


def test_401_keeps_cors_headers_for_the_web_app(anonymous: TestClient) -> None:
    response = anonymous.get("/notebooks", headers={"Origin": "http://localhost:5173"})
    assert response.status_code == 401
    assert response.headers["access-control-allow-origin"] == "http://localhost:5173"


# --- Origen de la conexión (defensa adicional, no sustituye al token) ----


@pytest.mark.parametrize("host", ["8.8.8.8", "100.64.1.1", "testclient", "2001:4860::8888"])
def test_non_local_origins_are_rejected_even_with_token(
    host: str, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    with _client_from(host, tmp_path, monkeypatch) as remote:
        for path in ("/notebooks", "/health"):
            response = remote.get(path)
            assert response.status_code == 403
            assert response.json()["error"]["code"] == "forbidden_origin"


@pytest.mark.parametrize("host", ["192.168.1.20", "10.0.0.5", "172.20.1.1", "::1", "fd00::1"])
def test_lan_origins_still_need_token(
    host: str, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    with _client_from(host, tmp_path, monkeypatch) as lan:
        assert lan.get("/notebooks").status_code == 200
        assert lan.get("/notebooks", headers={"Authorization": ""}).status_code == 401


def test_extra_networks_can_be_allowed(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("EULER_ALLOWED_NETWORKS", "100.64.0.0/10")
    with _client_from("100.64.1.1", tmp_path, monkeypatch) as vpn:
        assert vpn.get("/notebooks").status_code == 200


def test_ipv4_mapped_addresses_are_classified() -> None:
    assert security.is_allowed_client("::ffff:192.168.1.5", [])
    assert not security.is_allowed_client("::ffff:8.8.8.8", [])
    assert not security.is_allowed_client(None, [])


# --- Archivo del token ---------------------------------------------------


def test_token_file_is_created_private_and_reused(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.delenv("EULER_API_TOKEN")
    first = security.load_or_create_token(tmp_path)
    path = tmp_path / security.TOKEN_FILE_NAME
    assert len(first) >= 40
    assert stat.S_IMODE(os.stat(path).st_mode) == 0o600
    assert security.load_or_create_token(tmp_path) == first


def test_server_uses_token_file_when_no_env(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.delenv("EULER_API_TOKEN")
    monkeypatch.setenv("CUADERNO_DB_PATH", str(tmp_path / "test.db"))
    with make_client(headers={}) as fresh:
        token = (tmp_path / security.TOKEN_FILE_NAME).read_text().strip()
        assert fresh.get("/notebooks").status_code == 401
        ok = fresh.get("/notebooks", headers={"Authorization": f"Bearer {token}"})
        assert ok.status_code == 200


def test_short_env_token_is_rejected(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("EULER_API_TOKEN", "corto")
    with pytest.raises(ValueError):
        security.load_or_create_token(tmp_path)


def test_importing_main_creates_no_files(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("EULER_API_TOKEN")
    monkeypatch.setenv("CUADERNO_DB_PATH", str(tmp_path / "test.db"))
    from app.main import create_app

    create_app()
    assert not (tmp_path / security.TOKEN_FILE_NAME).exists()


# --- Límite de tareas simultáneas ---------------------------------------


def test_busy_server_answers_503(client: TestClient, monkeypatch: pytest.MonkeyPatch) -> None:
    slots = threading.BoundedSemaphore(1)
    monkeypatch.setattr(sandbox, "_slots", slots)
    monkeypatch.setattr(sandbox, "QUEUE_TIMEOUT", 0.05)
    slots.acquire()  # otra tarea ocupa el único hueco
    try:
        response = client.post("/compute", json={"expr": "x**2", "op": "diff"})
    finally:
        slots.release()
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "server_busy"
    # Con el hueco libre vuelve a funcionar.
    assert client.post("/compute", json={"expr": "x**2", "op": "diff"}).status_code == 200


def test_slot_is_released_after_errors(client: TestClient, monkeypatch: pytest.MonkeyPatch) -> None:
    slots = threading.BoundedSemaphore(1)
    monkeypatch.setattr(sandbox, "_slots", slots)
    assert client.post("/compute", json={"expr": "x +* 2", "op": "diff"}).status_code == 400
    assert slots.acquire(blocking=False)  # el hueco quedó libre
    slots.release()


def test_local_client_constant_is_loopback() -> None:
    assert security.is_allowed_client(LOCAL_CLIENT[0], [])
