import pytest
from fastapi.testclient import TestClient


def _create(client: TestClient, title: str = "Cálculo I") -> dict:
    response = client.post("/notebooks", json={"title": title})
    assert response.status_code == 201
    return response.json()


def test_create_and_list(client: TestClient) -> None:
    assert client.get("/notebooks").json() == []
    created = _create(client)
    assert created["title"] == "Cálculo I"
    assert created["created_at"] == created["updated_at"]
    assert client.get("/notebooks").json() == [created]


def test_get_notebook(client: TestClient) -> None:
    created = _create(client)
    assert client.get(f"/notebooks/{created['id']}").json() == created


def test_title_is_trimmed_and_required(client: TestClient) -> None:
    assert _create(client, "  Física  ")["title"] == "Física"
    response = client.post("/notebooks", json={"title": "   "})
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"


def test_rename(client: TestClient) -> None:
    created = _create(client)
    response = client.put(f"/notebooks/{created['id']}", json={"title": "Álgebra"})
    assert response.status_code == 200
    body = response.json()
    assert body["title"] == "Álgebra"
    assert body["updated_at"] > created["updated_at"]


def test_delete_cascades_to_notes(client: TestClient) -> None:
    notebook = _create(client)
    note = client.post(f"/notebooks/{notebook['id']}/notes", json={"title": "n"}).json()

    assert client.delete(f"/notebooks/{notebook['id']}").status_code == 204
    assert client.get(f"/notebooks/{notebook['id']}").status_code == 404
    assert client.get(f"/notes/{note['id']}").status_code == 404


def test_missing_notebook_returns_404(client: TestClient) -> None:
    for method, path, body in [
        ("GET", "/notebooks/999", None),
        ("PUT", "/notebooks/999", {"title": "x"}),
        ("DELETE", "/notebooks/999", None),
        ("GET", "/notebooks/999/notes", None),
        ("POST", "/notebooks/999/notes", {"title": "x"}),
    ]:
        response = client.request(method, path, json=body)
        assert response.status_code == 404, (method, path)
        assert response.json()["error"]["code"] == "not_found"


def test_data_persists_across_restarts(tmp_path, monkeypatch) -> None:
    from app.main import create_app

    monkeypatch.setenv("CUADERNO_DB_PATH", str(tmp_path / "persist.db"))
    with TestClient(create_app()) as first:
        first.post("/notebooks", json={"title": "Persistente"})
    with TestClient(create_app()) as second:
        titles = [nb["title"] for nb in second.get("/notebooks").json()]
    assert titles == ["Persistente"]


def test_cover_default_create_and_update(client: TestClient) -> None:
    assert _create(client)["cover"] == "classic"

    created = client.post("/notebooks", json={"title": "Cosmos", "cover": "sagan"}).json()
    assert created["cover"] == "sagan"

    updated = client.put(f"/notebooks/{created['id']}", json={"cover": "astronomy"}).json()
    assert updated["cover"] == "astronomy"
    assert updated["title"] == "Cosmos"


@pytest.mark.parametrize("cover", ["Física", "a b", "", "x" * 40])
def test_invalid_cover(client: TestClient, cover: str) -> None:
    response = client.post("/notebooks", json={"title": "T", "cover": cover})
    assert response.status_code == 422


def test_migrates_v01_database(tmp_path, monkeypatch) -> None:
    """Una base de datos de la v0.1 se actualiza sin perder datos."""
    import sqlite3
    from pathlib import Path

    from app.main import create_app

    db_path = tmp_path / "v01.db"
    schema = (Path(__file__).parent.parent / "app" / "storage" / "schema.sql").read_text()
    with sqlite3.connect(db_path) as conn:
        conn.executescript(schema)
        conn.execute(
            "INSERT INTO notebooks (title, created_at, updated_at) VALUES ('Viejo', 't', 't')"
        )
        conn.execute(
            "INSERT INTO notes (notebook_id, title, content, created_at, updated_at) "
            "VALUES (1, 'Nota', 'x', 't', 't')"
        )
    conn.close()

    monkeypatch.setenv("CUADERNO_DB_PATH", str(db_path))
    with TestClient(create_app()) as client:
        notebook = client.get("/notebooks").json()[0]
        assert (notebook["title"], notebook["cover"]) == ("Viejo", "classic")
        note = client.get("/notes/1").json()
        assert (note["content"], note["paper"]) == ("x", "blank")
        assert client.get("/documents").json() == []

    with sqlite3.connect(db_path) as conn:
        assert conn.execute("PRAGMA user_version").fetchone()[0] == 1
    conn.close()
    with TestClient(create_app()) as client:  # segunda vez: no repite migraciones
        assert client.get("/notebooks").status_code == 200
