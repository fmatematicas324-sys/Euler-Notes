import pytest
from fastapi.testclient import TestClient

from app.api import documents as documents_api
from app.services.pdf import unicode_to_latex


def _upload(client: TestClient, data: bytes, filename: str = "apuntes.pdf"):
    return client.post(
        "/documents",
        params={"filename": filename},
        content=data,
        headers={"Content-Type": "application/pdf"},
    )


def test_upload_list_get_and_download(client: TestClient, sample_pdf: bytes) -> None:
    response = _upload(client, sample_pdf)
    assert response.status_code == 201, response.text
    document = response.json()
    assert document["filename"] == "apuntes.pdf"
    assert document["pages"] == 2
    assert document["size"] == len(sample_pdf)

    assert client.get("/documents").json() == [document]
    assert client.get(f"/documents/{document['id']}").json() == document

    file = client.get(f"/documents/{document['id']}/file")
    assert file.status_code == 200
    assert file.headers["content-type"] == "application/pdf"
    assert file.content == sample_pdf


def test_filename_is_sanitized(client: TestClient, sample_pdf: bytes) -> None:
    document = _upload(client, sample_pdf, "../../etc/malicioso.pdf").json()
    assert document["filename"] == "malicioso.pdf"


def test_page_text_and_latex(client: TestClient, sample_pdf: bytes) -> None:
    document_id = _upload(client, sample_pdf).json()["id"]

    first = client.get(f"/documents/{document_id}/pages/1/text").json()
    assert first["page"] == 1
    assert "∮" in first["text"]
    assert r"\oint" in first["latex"]
    assert r"\epsilon" in first["latex"]

    second = client.get(f"/documents/{document_id}/pages/2/text").json()
    assert r"\partial" in second["latex"]
    assert r"\nabla ^{2}" in second["latex"]


@pytest.mark.parametrize("page", [0, 3])
def test_missing_page(client: TestClient, sample_pdf: bytes, page: int) -> None:
    document_id = _upload(client, sample_pdf).json()["id"]
    response = client.get(f"/documents/{document_id}/pages/{page}/text")
    assert response.status_code == 404


def test_not_a_pdf(client: TestClient) -> None:
    response = _upload(client, b"hola, no soy un PDF")
    assert response.status_code == 400
    assert response.json()["error"]["code"] == "invalid_pdf"


def test_corrupted_pdf(client: TestClient) -> None:
    response = _upload(client, b"%PDF-1.7\n esto no es un PDF de verdad")
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "invalid_pdf"
    assert client.get("/documents").json() == []


def test_too_large(client: TestClient, sample_pdf: bytes, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(documents_api, "MAX_PDF_BYTES", 100)
    response = _upload(client, sample_pdf)
    assert response.status_code == 413
    assert response.json()["error"]["code"] == "file_too_large"


def test_delete(client: TestClient, sample_pdf: bytes) -> None:
    document_id = _upload(client, sample_pdf).json()["id"]
    assert client.delete(f"/documents/{document_id}").status_code == 204
    assert client.get(f"/documents/{document_id}").status_code == 404
    assert client.get(f"/documents/{document_id}/file").status_code == 404
    assert client.delete(f"/documents/{document_id}").status_code == 404


@pytest.mark.parametrize(
    ("text", "latex"),
    [
        ("E = mc²", "E = mc^{2}"),
        ("x₁₂ + y⁻¹", "x_{12} + y^{-1}"),
        ("∫ f dx ≤ ∞", r"\int f dx \leq \infty"),
        ("α + Ω", r"\alpha + \Omega"),
        ("v ∈ ℝ³", r"v \in \mathbb{R}^{3}"),
        ("30° y 50%", r"30^{\circ} y 50\%"),
        ("texto normal", "texto normal"),
    ],
)
def test_unicode_to_latex(text: str, latex: str) -> None:
    assert unicode_to_latex(text) == latex
