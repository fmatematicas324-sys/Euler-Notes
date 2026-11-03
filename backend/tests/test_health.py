from fastapi.testclient import TestClient

from app.config import VERSION


def test_health_ok(client: TestClient) -> None:
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok", "version": VERSION}


def test_unknown_route_uses_error_format(client: TestClient) -> None:
    response = client.get("/no-existe")
    assert response.status_code == 404
    assert response.json()["error"]["code"] == "not_found"


def test_cors_allows_localhost_only(client: TestClient) -> None:
    allowed = client.get("/health", headers={"Origin": "http://localhost:5173"})
    assert allowed.headers.get("access-control-allow-origin") == "http://localhost:5173"

    denied = client.get("/health", headers={"Origin": "https://evil.example.com"})
    assert "access-control-allow-origin" not in denied.headers
