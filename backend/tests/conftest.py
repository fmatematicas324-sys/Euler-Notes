from collections.abc import Iterator
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.main import create_app


@pytest.fixture
def client(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Iterator[TestClient]:
    """Cliente de pruebas con una base de datos SQLite temporal y aislada."""
    monkeypatch.setenv("CUADERNO_DB_PATH", str(tmp_path / "test.db"))
    with TestClient(create_app()) as test_client:
        yield test_client
