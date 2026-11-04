"""Lectura de PDF con pypdf. Se ejecuta en el subproceso aislado (`sandbox`):
los PDF son archivos no confiables y pypdf puede tardar o consumir mucha memoria
con documentos malformados.

La extracción de fórmulas es aproximada: un PDF solo guarda glifos colocados en la
página, no LaTeX. `unicode_to_latex` traduce los símbolos matemáticos Unicode más
comunes para que el usuario solo tenga que retocar la estructura.
"""

import re

from pypdf import PdfReader
from pypdf.errors import PdfReadError

from app.services.sympy_engine import ComputeFailure


def _open(path: str) -> PdfReader:
    try:
        reader = PdfReader(path)
        if reader.is_encrypted and not reader.decrypt(""):
            raise ComputeFailure("El PDF está protegido con contraseña")
        return reader
    except ComputeFailure:
        raise
    except (PdfReadError, ValueError, OSError, KeyError) as exc:
        raise ComputeFailure("El archivo no es un PDF válido o está dañado") from exc


def count_pages(path: str) -> int:
    pages = len(_open(path).pages)
    if pages == 0:
        raise ComputeFailure("El PDF no tiene páginas")
    return pages


def extract_page(path: str, page: int) -> tuple[str, str]:
    """Texto de la página `page` (desde 1) y su versión aproximada en LaTeX."""
    reader = _open(path)
    if not 1 <= page <= len(reader.pages):
        raise ComputeFailure(f"La página {page} no existe (el PDF tiene {len(reader.pages)})")
    try:
        text = reader.pages[page - 1].extract_text() or ""
    except Exception as exc:
        raise ComputeFailure("No se pudo extraer el texto de esta página") from exc
    text = _clean(text)
    return text, unicode_to_latex(text)


def _clean(text: str) -> str:
    text = text.replace("\r\n", "\n").replace(" ", " ")
    text = re.sub(r"[ \t]+\n", "\n", text)
    return re.sub(r"\n{3,}", "\n\n", text).strip()


# --- Unicode → LaTeX (aproximado) -----------------------------------------------

_GREEK = {
    "α": "alpha", "β": "beta", "γ": "gamma", "δ": "delta", "ε": "epsilon", "ϵ": "epsilon",
    "ζ": "zeta", "η": "eta", "θ": "theta", "ϑ": "vartheta", "ι": "iota", "κ": "kappa",
    "λ": "lambda", "μ": "mu", "ν": "nu", "ξ": "xi", "π": "pi", "ρ": "rho", "σ": "sigma",
    "τ": "tau", "υ": "upsilon", "φ": "phi", "ϕ": "phi", "χ": "chi", "ψ": "psi", "ω": "omega",
    "Γ": "Gamma", "Δ": "Delta", "Θ": "Theta", "Λ": "Lambda", "Ξ": "Xi", "Π": "Pi",
    "Σ": "Sigma", "Φ": "Phi", "Ψ": "Psi", "Ω": "Omega",
}  # fmt: skip
_SYMBOLS = {
    "∫": r"\int", "∬": r"\iint", "∭": r"\iiint", "∮": r"\oint", "∂": r"\partial",
    "∇": r"\nabla", "∞": r"\infty", "∑": r"\sum", "∏": r"\prod", "√": r"\sqrt",
    "±": r"\pm", "∓": r"\mp", "×": r"\times", "·": r"\cdot", "⋅": r"\cdot", "÷": r"\div",
    "≤": r"\leq", "≥": r"\geq", "≠": r"\neq", "≈": r"\approx", "≡": r"\equiv",
    "∝": r"\propto", "∼": r"\sim", "→": r"\to", "←": r"\leftarrow", "⇒": r"\Rightarrow",
    "⇔": r"\Leftrightarrow", "↔": r"\leftrightarrow", "∈": r"\in", "∉": r"\notin",
    "⊂": r"\subset", "⊆": r"\subseteq", "∪": r"\cup", "∩": r"\cap", "∀": r"\forall",
    "∃": r"\exists", "∅": r"\emptyset", "ℏ": r"\hbar", "∘": r"\circ", "⟨": r"\langle",
    "⟩": r"\rangle", "‖": r"\|", "ℝ": r"\mathbb{R}", "ℕ": r"\mathbb{N}",
    "ℤ": r"\mathbb{Z}", "ℚ": r"\mathbb{Q}", "ℂ": r"\mathbb{C}", "°": r"^{\circ}",
    "−": "-", "′": "'", "″": "''", "…": r"\ldots", "⋯": r"\cdots",
}  # fmt: skip
_SUPERSCRIPTS = dict(zip("⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻⁼⁽⁾ⁿⁱ", "0123456789+-=()ni", strict=True))
_SUBSCRIPTS = dict(zip("₀₁₂₃₄₅₆₇₈₉₊₋₌₍₎ₐₑₒₓₙ", "0123456789+-=()aeoxn", strict=True))
_ESCAPES = {"%": r"\%", "&": r"\&", "#": r"\#"}


def unicode_to_latex(text: str) -> str:
    out: list[str] = []
    i = 0
    while i < len(text):
        char = text[i]
        for table, marker in ((_SUPERSCRIPTS, "^"), (_SUBSCRIPTS, "_")):
            if char in table:
                run = ""
                while i < len(text) and text[i] in table:
                    run += table[text[i]]
                    i += 1
                out.append(f"{marker}{{{run}}}")
                break
        else:
            if char in _GREEK:
                out.append(f"\\{_GREEK[char]} ")
            elif char in _SYMBOLS:
                command = _SYMBOLS[char]
                out.append(command + (" " if command[-1].isalpha() else ""))
            else:
                out.append(_ESCAPES.get(char, char))
            i += 1
    return re.sub(r" {2,}", " ", "".join(out)).strip()
