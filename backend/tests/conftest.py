from collections.abc import Iterator
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.main import create_app

# Token fijo para las pruebas (el real se genera en backend/data/api_token).
TEST_TOKEN = "token-de-pruebas-0123456789abcdef"
LOCAL_CLIENT = ("127.0.0.1", 50000)


def make_client(**kwargs: object) -> TestClient:
    """TestClient autenticado que simula una conexión desde el propio equipo.
    (Por defecto Starlette usa el host "testclient", que no es una IP.)"""
    options: dict[str, object] = {
        "client": LOCAL_CLIENT,
        "headers": {"Authorization": f"Bearer {TEST_TOKEN}"},
    }
    options.update(kwargs)
    return TestClient(create_app(), **options)  # type: ignore[arg-type]


@pytest.fixture(autouse=True)
def _api_token(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("CUADERNO_API_TOKEN", raising=False)
    monkeypatch.setenv("EULER_API_TOKEN", TEST_TOKEN)


@pytest.fixture
def client(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Iterator[TestClient]:
    """Cliente de pruebas con una base de datos SQLite temporal y aislada."""
    monkeypatch.setenv("CUADERNO_DB_PATH", str(tmp_path / "test.db"))
    with make_client() as test_client:
        yield test_client


@pytest.fixture(scope="session")
def sample_pdf(tmp_path_factory: pytest.TempPathFactory) -> bytes:
    """PDF de 2 páginas con texto y símbolos matemáticos (generado con matplotlib)."""
    import matplotlib

    matplotlib.use("Agg")
    from matplotlib.backends.backend_pdf import PdfPages
    from matplotlib.figure import Figure

    path = tmp_path_factory.mktemp("pdf") / "muestra.pdf"
    with matplotlib.rc_context({"pdf.fonttype": 42}), PdfPages(path) as pdf:
        for text in ("Gauss: ∮ E·dA = Q/ε₀", "Calor: ∂u/∂t = α ∇²u"):
            fig = Figure(figsize=(6, 4))
            fig.text(0.1, 0.5, text, fontsize=14)
            pdf.savefig(fig)
    return path.read_bytes()
