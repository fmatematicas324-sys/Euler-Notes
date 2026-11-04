import pytest
from fastapi.testclient import TestClient


@pytest.fixture
def notebook_id(client: TestClient) -> int:
    return client.post("/notebooks", json={"title": "Física"}).json()["id"]


def test_create_list_and_get(client: TestClient, notebook_id: int) -> None:
    content = "Energía: $E = mc^2$\n\n$$\\int x^2\\,dx$$"
    response = client.post(
        f"/notebooks/{notebook_id}/notes", json={"title": "Relatividad", "content": content}
    )
    assert response.status_code == 201
    note = response.json()
    assert note["content"] == content
    assert note["notebook_id"] == notebook_id

    summaries = client.get(f"/notebooks/{notebook_id}/notes").json()
    assert len(summaries) == 1
    assert "content" not in summaries[0]

    assert client.get(f"/notes/{note['id']}").json() == note


def test_content_defaults_to_empty(client: TestClient, notebook_id: int) -> None:
    note = client.post(f"/notebooks/{notebook_id}/notes", json={"title": "Vacía"}).json()
    assert note["content"] == ""


def test_partial_update(client: TestClient, notebook_id: int) -> None:
    note = client.post(
        f"/notebooks/{notebook_id}/notes", json={"title": "T", "content": "a"}
    ).json()

    updated = client.put(f"/notes/{note['id']}", json={"content": "b"}).json()
    assert updated["title"] == "T"
    assert updated["content"] == "b"
    assert updated["updated_at"] > note["updated_at"]

    renamed = client.put(f"/notes/{note['id']}", json={"title": "T2"}).json()
    assert renamed["title"] == "T2"
    assert renamed["content"] == "b"


def test_delete_note(client: TestClient, notebook_id: int) -> None:
    note = client.post(f"/notebooks/{notebook_id}/notes", json={"title": "x"}).json()
    assert client.delete(f"/notes/{note['id']}").status_code == 204
    assert client.get(f"/notes/{note['id']}").status_code == 404
    assert client.get(f"/notebooks/{notebook_id}/notes").json() == []


def test_missing_note_returns_404(client: TestClient) -> None:
    assert client.get("/notes/999").status_code == 404
    assert client.put("/notes/999", json={"title": "x"}).status_code == 404
    assert client.delete("/notes/999").status_code == 404


def test_empty_title_rejected_on_update(client: TestClient, notebook_id: int) -> None:
    note = client.post(f"/notebooks/{notebook_id}/notes", json={"title": "x"}).json()
    assert client.put(f"/notes/{note['id']}", json={"title": ""}).status_code == 422


def test_paper_default_and_update(client: TestClient, notebook_id: int) -> None:
    note = client.post(f"/notebooks/{notebook_id}/notes", json={"title": "x"}).json()
    assert note["paper"] == "blank"

    updated = client.put(f"/notes/{note['id']}", json={"paper": "grid"}).json()
    assert updated["paper"] == "grid"
    assert client.get(f"/notebooks/{notebook_id}/notes").json()[0]["paper"] == "grid"

    created = client.post(
        f"/notebooks/{notebook_id}/notes", json={"title": "y", "paper": "semilog"}
    ).json()
    assert created["paper"] == "semilog"
