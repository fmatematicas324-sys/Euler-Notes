import ipaddress
from pathlib import Path

import pytest

from app import pair
from app.security import TOKEN_FILE_NAME


def test_lan_address_is_an_ip() -> None:
    ipaddress.ip_address(pair.lan_address())


def test_render_contains_url_token_and_qr() -> None:
    text = pair.render("http://192.168.1.5:8000", "token-de-ejemplo-123456")
    assert "http://192.168.1.5:8000" in text
    assert "token-de-ejemplo-123456" in text
    assert "█" in text or "▀" in text or "▄" in text  # QR dibujado con bloques (segno)


def test_render_without_qr() -> None:
    text = pair.render("http://10.0.0.2:8000", "abc", with_qr=False)
    assert "█" not in text and "▀" not in text


def test_rotate_creates_a_different_token(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("EULER_API_TOKEN", raising=False)
    (tmp_path / TOKEN_FILE_NAME).write_text("token-antiguo-0123456789abcdef", encoding="utf-8")
    new = pair.rotate_token(tmp_path)
    assert new != "token-antiguo-0123456789abcdef"
    assert (tmp_path / TOKEN_FILE_NAME).read_text(encoding="utf-8").strip() == new
    assert (tmp_path / TOKEN_FILE_NAME).stat().st_mode & 0o777 == 0o600


def test_rotate_refuses_when_token_comes_from_env(tmp_path: Path) -> None:
    # conftest fija EULER_API_TOKEN en todas las pruebas.
    with pytest.raises(RuntimeError):
        pair.rotate_token(tmp_path)


def test_main_prints_address_and_token(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.delenv("EULER_API_TOKEN", raising=False)
    monkeypatch.setenv("EULER_DB_PATH", str(tmp_path / "cuaderno.db"))
    assert pair.main(["--sin-qr", "--puerto", "9000"]) == 0
    out = capsys.readouterr().out
    token = (tmp_path / TOKEN_FILE_NAME).read_text(encoding="utf-8").strip()
    assert token in out
    assert ":9000" in out
