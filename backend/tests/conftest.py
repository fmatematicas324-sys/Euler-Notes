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
