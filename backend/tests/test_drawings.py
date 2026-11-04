import pytest
from fastapi.testclient import TestClient

from app.domain.models import MAX_POINTS_PER_STROKE


@pytest.fixture
def note_id(client: TestClient) -> int:
    notebook = client.post("/notebooks", json={"title": "Física"}).json()
    return client.post(f"/notebooks/{notebook['id']}/notes", json={"title": "N"}).json()["id"]


STROKE = {
    "tool": "pen",
    "color": "#1c64d9",
    "width": 3,
    "points": [10, 20, 0.5, 15.5, 25, 0.8, 20, 30, 1.0],
}


def test_create_get_update_delete(client: TestClient, note_id: int) -> None:
    created = client.post(f"/notes/{note_id}/drawings", json={}).json()
    assert created["note_id"] == note_id
    assert (created["width"], created["height"]) == (1000, 700)
    assert created["strokes"] == []

    updated = client.put(f"/drawings/{created['id']}", json={"strokes": [STROKE]}).json()
    assert updated["strokes"] == [{**STROKE, "width": 3.0}]
    assert updated["updated_at"] > created["updated_at"]
    assert client.get(f"/drawings/{created['id']}").json() == updated

    resized = client.put(f"/drawings/{created['id']}", json={"height": 1400}).json()
    assert resized["height"] == 1400
    assert len(resized["strokes"]) == 1

    assert client.delete(f"/drawings/{created['id']}").status_code == 204
    assert client.get(f"/drawings/{created['id']}").status_code == 404


def test_defaults_for_stroke(client: TestClient, note_id: int) -> None:
    drawing = client.post(
        f"/notes/{note_id}/drawings", json={"strokes": [{"points": [1, 2, 0.3]}]}
    ).json()
    stroke = drawing["strokes"][0]
    assert (stroke["tool"], stroke["color"], stroke["width"]) == ("pen", "#1B1F24", 3.0)


def test_drawings_are_deleted_with_their_note(client: TestClient, note_id: int) -> None:
    drawing_id = client.post(f"/notes/{note_id}/drawings", json={}).json()["id"]
    client.delete(f"/notes/{note_id}")
    assert client.get(f"/drawings/{drawing_id}").status_code == 404


def test_missing(client: TestClient) -> None:
    assert client.post("/notes/999/drawings", json={}).status_code == 404
    assert client.get("/drawings/999").status_code == 404
    assert client.put("/drawings/999", json={}).status_code == 404
    assert client.delete("/drawings/999").status_code == 404


@pytest.mark.parametrize(
    "stroke",
    [
        {**STROKE, "points": [1, 2]},  # no es múltiplo de 3
        {**STROKE, "points": []},
        {**STROKE, "points": [1, 2, 1.5]},  # presión > 1
        {**STROKE, "color": "azul"},
        {**STROKE, "tool": "spray"},
        {**STROKE, "width": 0},
        {**STROKE, "points": [0, 0, 0.5] * (MAX_POINTS_PER_STROKE + 1)},
    ],
)
def test_invalid_strokes(client: TestClient, note_id: int, stroke: dict) -> None:
    response = client.post(f"/notes/{note_id}/drawings", json={"strokes": [stroke]})
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"


def test_invalid_canvas_size(client: TestClient, note_id: int) -> None:
    assert client.post(f"/notes/{note_id}/drawings", json={"width": 10}).status_code == 422
