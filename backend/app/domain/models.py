"""Modelos Pydantic de entrada y salida de la API."""

from typing import Annotated, Literal

from pydantic import BaseModel, Field, StringConstraints, model_validator

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


# --- Gráficas ------------------------------------------------------------------

Coordinate = Annotated[float, Field(allow_inf_nan=False, ge=-1e6, le=1e6)]


class PlotRequest(BaseModel):
    exprs: Annotated[list[Expression], Field(min_length=1, max_length=5)]
    var: VariableName = "x"
    x_min: Coordinate = -10.0
    x_max: Coordinate = 10.0
    y_min: Coordinate | None = None
    y_max: Coordinate | None = None
    theme: Literal["light", "dark"] = "light"
    width: Annotated[int, Field(ge=200, le=1600)] = 800
    height: Annotated[int, Field(ge=150, le=1200)] = 500
    scale: Annotated[float, Field(ge=1, le=3)] = 1.0

    @model_validator(mode="after")
    def _check_ranges(self) -> "PlotRequest":
        if self.x_min >= self.x_max:
            raise ValueError("x_min debe ser menor que x_max")
        if (self.y_min is None) != (self.y_max is None):
            raise ValueError("Indica y_min e y_max juntos, o ninguno para rango automático")
        if self.y_min is not None and self.y_max is not None and self.y_min >= self.y_max:
            raise ValueError("y_min debe ser menor que y_max")
        return self
