from pathlib import Path

import pytest

from app import config


def test_version_matches_pyproject() -> None:
    import tomllib

    pyproject = Path(config.__file__).resolve().parents[1] / "pyproject.toml"
    with pyproject.open("rb") as file:
        assert config.VERSION == tomllib.load(file)["project"]["version"]


def test_euler_prefix_is_read(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("CUADERNO_COMPUTE_TIMEOUT", raising=False)
    monkeypatch.setenv("EULER_COMPUTE_TIMEOUT", "7")
    assert config.get_compute_timeout() == 7


def test_legacy_prefix_still_works(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("EULER_PDF_TIMEOUT", raising=False)
    monkeypatch.setenv("CUADERNO_PDF_TIMEOUT", "9")
    assert config.get_pdf_timeout() == 9


def test_euler_prefix_wins(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    monkeypatch.setenv("CUADERNO_DB_PATH", str(tmp_path / "antigua.db"))
    monkeypatch.setenv("EULER_DB_PATH", str(tmp_path / "nueva.db"))
    assert config.get_db_path() == tmp_path / "nueva.db"
