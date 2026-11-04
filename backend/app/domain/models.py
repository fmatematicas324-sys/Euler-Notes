"""Modelos Pydantic de entrada y salida de la API."""

from typing import Annotated, Literal

from pydantic import BaseModel, Field, StringConstraints, model_validator

Title = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=200)]
Content = Annotated[str, StringConstraints(max_length=200_000)]
# Identificador de estilo (portada, papel). El catálogo vive en la app: el backend
# solo valida la forma para no romper clientes con estilos nuevos.
StyleId = Annotated[str, StringConstraints(pattern=r"^[a-z][a-z0-9_]{0,31}$")]


class NotebookIn(BaseModel):
    title: Title
    cover: StyleId = "classic"


class NotebookUpdate(BaseModel):
    title: Title | None = None
    cover: StyleId | None = None


class Notebook(BaseModel):
    id: int
    title: str
    cover: str
    created_at: str
    updated_at: str


class NoteCreate(BaseModel):
    title: Title
    content: Content = ""
    paper: StyleId = "blank"


class NoteUpdate(BaseModel):
    title: Title | None = None
    content: Content | None = None
    paper: StyleId | None = None


class NoteSummary(BaseModel):
    id: int
    notebook_id: int
    title: str
    paper: str
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


class FigureOptions(BaseModel):
    """Aspecto de la imagen: tema, tamaño en px lógicos y densidad de píxeles."""

    theme: Literal["light", "dark"] = "light"
    width: Annotated[int, Field(ge=200, le=1600)] = 800
    height: Annotated[int, Field(ge=150, le=1200)] = 500
    scale: Annotated[float, Field(ge=1, le=3)] = 1.0


class PlotRequest(FigureOptions):
    exprs: Annotated[list[Expression], Field(min_length=1, max_length=5)]
    var: VariableName = "x"
    x_min: Coordinate = -10.0
    x_max: Coordinate = 10.0
    y_min: Coordinate | None = None
    y_max: Coordinate | None = None

    @model_validator(mode="after")
    def _check_ranges(self) -> "PlotRequest":
        if self.x_min >= self.x_max:
            raise ValueError("x_min debe ser menor que x_max")
        if (self.y_min is None) != (self.y_max is None):
            raise ValueError("Indica y_min e y_max juntos, o ninguno para rango automático")
        if self.y_min is not None and self.y_max is not None and self.y_min >= self.y_max:
            raise ValueError("y_min debe ser menor que y_max")
        return self


# --- Documentos PDF ------------------------------------------------------------


class Document(BaseModel):
    id: int
    filename: str
    size: int
    pages: int
    created_at: str


class DocumentPageText(BaseModel):
    page: int
    text: str
    latex: str


# --- Diagramas -----------------------------------------------------------------

# Etiquetas visibles en el diagrama: sin `$` (mathtext) ni caracteres de control.
DiagramLabel = Annotated[
    str,
    StringConstraints(
        strip_whitespace=True, min_length=1, max_length=24, pattern=r"^[\w .,()+'\-]+$"
    ),
]
Finite = Annotated[float, Field(allow_inf_nan=False)]


class FunctionDiagram(FigureOptions):
    kind: Literal["function"]
    expr: Expression
    op: ComputeOp
    var: VariableName = "x"
    x_min: Coordinate = -10.0
    x_max: Coordinate = 10.0

    @model_validator(mode="after")
    def _check_range(self) -> "FunctionDiagram":
        if self.x_min >= self.x_max:
            raise ValueError("x_min debe ser menor que x_max")
        return self


class Force(BaseModel):
    label: DiagramLabel
    magnitude: Annotated[float, Field(gt=0, le=1e6, allow_inf_nan=False)]
    angle: Annotated[float, Field(ge=-360, le=360, allow_inf_nan=False)]


class ForcesDiagram(FigureOptions):
    kind: Literal["forces"]
    forces: Annotated[list[Force], Field(min_length=1, max_length=8)]
    show_resultant: bool = True


class ProjectileDiagram(FigureOptions):
    kind: Literal["projectile"]
    v0: Annotated[float, Field(gt=0, le=1e4, allow_inf_nan=False)]
    angle: Annotated[float, Field(gt=0, le=90, allow_inf_nan=False)]
    g: Annotated[float, Field(gt=0, le=1000, allow_inf_nan=False)] = 9.81
    h0: Annotated[float, Field(ge=0, le=1e5, allow_inf_nan=False)] = 0.0


class Edge(BaseModel):
    source: DiagramLabel
    target: DiagramLabel
    weight: Finite | None = None


class GraphDiagram(FigureOptions):
    kind: Literal["graph"]
    edges: Annotated[list[Edge], Field(min_length=1, max_length=60)]
    directed: bool = False


DiagramRequest = Annotated[
    FunctionDiagram | ForcesDiagram | ProjectileDiagram | GraphDiagram,
    Field(discriminator="kind"),
]
