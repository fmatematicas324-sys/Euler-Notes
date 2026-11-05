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


# --- Política explícita de redes (M1) -------------------------------------

ALLOWED_HOSTS = {
    "loopback IPv4": ["127.0.0.1", "127.255.255.254"],
    "loopback IPv6": ["::1"],
    "RFC 1918": [
        "10.0.0.1",
        "10.255.255.255",
        "172.16.0.0",
        "172.31.255.255",
        "192.168.0.1",
        "192.168.255.255",
    ],
    "link-local IPv4": ["169.254.0.1", "169.254.255.254"],
    "link-local IPv6": ["fe80::1", "fe80::1%eth0", "febf:ffff::1"],
    "ULA": ["fc00::1", "fd12:3456::1", "fdff:ffff::1"],
    "IPv4-mapped permitida": ["::ffff:127.0.0.1", "::ffff:192.168.1.5", "::ffff:169.254.1.1"],
}

REJECTED_HOSTS = {
    "IPv4 pública": ["8.8.8.8", "1.1.1.1", "172.15.255.255", "172.32.0.0", "11.0.0.1"],
    "IPv6 pública": ["2001:4860:4860::8888", "2a00:1450::1"],
    "Teredo": ["2001:0:4136:e378:8000:63bf:3fff:fdd2", "2001::1"],
    "6to4": ["2002:0808:0808::1", "2002:c0a8:0101::1"],  # el 2.º envuelve 192.168.1.1
    "no especificada": ["0.0.0.0", "0.1.2.3", "::"],
    "multicast": ["224.0.0.1", "239.255.255.250", "ff02::1", "ff05::2"],
    "broadcast": ["255.255.255.255"],
    "reservadas fuera de la lista": [
        "100.64.0.1",  # CGNAT
        "192.0.2.10",  # documentación
        "198.18.0.1",  # pruebas de rendimiento
        "240.0.0.1",  # reservada
        "2001:db8::1",  # documentación IPv6
        "fec0::1",  # site-local (obsoleta)
        "64:ff9b::808:808",  # NAT64
        "::8.8.8.8",  # IPv4-compatible (obsoleta)
    ],
    "IPv4-mapped rechazada": ["::ffff:8.8.8.8", "::ffff:224.0.0.1", "::ffff:0.0.0.0"],
    "no es una IP": ["", "testclient", "[::1]", "localhost", "192.168.1"],
}


@pytest.mark.parametrize(
    ("category", "host"),
    [(category, host) for category, hosts in ALLOWED_HOSTS.items() for host in hosts],
)
def test_allowed_categories(category: str, host: str) -> None:
    assert security.is_allowed_client(host, []), category


@pytest.mark.parametrize(
    ("category", "host"),
    [(category, host) for category, hosts in REJECTED_HOSTS.items() for host in hosts],
)
def test_rejected_categories(category: str, host: str) -> None:
    assert not security.is_allowed_client(host, []), category


def test_none_host_is_rejected() -> None:
    assert not security.is_allowed_client(None, [])


@pytest.mark.parametrize(
    "host", ["2001::1", "2002:0808:0808::1", "0.0.0.0", "::", "224.0.0.1", "ff02::1"]
)
def test_denied_networks_win_over_extra_networks(host: str) -> None:
    everything = [security.ipaddress.ip_network("0.0.0.0/0"), security.ipaddress.ip_network("::/0")]
    assert not security.is_allowed_client(host, everything)


def test_extra_networks_allow_only_what_they_list() -> None:
    vpn = [security.ipaddress.ip_network("100.64.0.0/10")]
    assert security.is_allowed_client("100.64.1.1", vpn)
    assert security.is_allowed_client("::ffff:100.64.1.1", vpn)
    assert not security.is_allowed_client("100.128.0.1", vpn)


def test_policy_does_not_use_is_private() -> None:
    # Teredo y 6to4 son "privadas" para Python, pero enrutables desde Internet.
    teredo = security.ipaddress.ip_address("2001::1")
    assert teredo.is_private
    assert not security.is_allowed_client(str(teredo), [])


@pytest.mark.parametrize(
    ("header", "value"),
    [
        ("X-Forwarded-For", "192.168.1.20"),
        ("x-forwarded-for", "127.0.0.1"),
        ("Forwarded", "for=192.168.1.20"),
        ("X-Real-IP", "10.0.0.2"),
    ],
)
def test_forwarding_headers_are_rejected(client: TestClient, header: str, value: str) -> None:
    for path in ("/notebooks", "/health"):
        response = client.get(path, headers={header: value})
        assert response.status_code == 403
        assert response.json()["error"]["code"] == "forwarded_not_allowed"


def test_forwarding_headers_cannot_unlock_a_public_origin(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    with _client_from("8.8.8.8", tmp_path, monkeypatch) as remote:
        response = remote.get("/notebooks", headers={"X-Forwarded-For": "127.0.0.1"})
        assert response.status_code == 403
