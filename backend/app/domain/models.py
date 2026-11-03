"""Modelos Pydantic de entrada y salida de la API."""

from typing import Annotated, Literal

from pydantic import BaseModel, StringConstraints

Title = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=200)]
Content = Annotated[str, StringConstraints(max_length=200_000)]


class NotebookIn(BaseModel):
    title: Title


class Notebook(BaseModel):
    id: int
    title: str
    created_at: str
    updated_at: str


class NoteCreate(BaseModel):
    title: Title
    content: Content = ""


class NoteUpdate(BaseModel):
    title: Title | None = None
    content: Content | None = None


class NoteSummary(BaseModel):
    id: int
    notebook_id: int
    title: str
    created_at: str
    updated_at: str


class Note(NoteSummary):
    content: str


# --- Cálculo simbólico -------------------------------------------------------

ComputeOp = Literal["simplify", "diff", "integrate", "solve"]
Expression = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=500)]
VariableName = Annotated[str, StringConstraints(pattern=r"^[A-Za-z][A-Za-z0-9]{0,19}$")]


class ComputeRequest(BaseModel):
    expr: Expression
    op: ComputeOp
    var: VariableName = "x"


class ComputeResponse(BaseModel):
    result_latex: str
    result_text: str
