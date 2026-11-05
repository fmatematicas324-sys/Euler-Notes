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


class PlaneRegion(FigureOptions):
    """Región rectangular del plano para funciones de dos variables."""

    var_x: VariableName = "x"
    var_y: VariableName = "y"
    x_min: Coordinate = -5.0
    x_max: Coordinate = 5.0
    y_min: Coordinate = -5.0
    y_max: Coordinate = 5.0

    @model_validator(mode="after")
    def _check_region(self) -> "PlaneRegion":
        if self.var_x == self.var_y:
            raise ValueError("var_x y var_y deben ser variables distintas")
        if self.x_min >= self.x_max:
            raise ValueError("x_min debe ser menor que x_max")
        if self.y_min >= self.y_max:
            raise ValueError("y_min debe ser menor que y_max")
        return self


class SurfaceDiagram(PlaneRegion):
    """Superficie z = f(x, y) en 3D, con curvas de nivel opcionales en la base."""

    kind: Literal["surface"]
    expr: Expression
    contours: bool = True


class ContourDiagram(PlaneRegion):
    """Curvas de nivel f(x, y) = c en el plano, rellenas o solo líneas."""

    kind: Literal["contour"]
    expr: Expression
    levels: Annotated[int, Field(ge=3, le=40)] = 12
    filled: bool = True


class VectorFieldDiagram(PlaneRegion):
    """Campo vectorial F = (P, Q) en el plano: flechas o líneas de campo."""

    kind: Literal["vector_field"]
    p: Expression
    q: Expression
    mode: Literal["arrows", "streamlines"] = "arrows"


class Curve3DDiagram(FigureOptions):
    """Curva paramétrica r(t) = (x(t), y(t), z(t)) en el espacio."""

    kind: Literal["curve3d"]
    x: Expression
    y: Expression
    z: Expression
    var: VariableName = "t"
    t_min: Coordinate = 0.0
    t_max: Coordinate = 10.0

    @model_validator(mode="after")
    def _check_range(self) -> "Curve3DDiagram":
        if self.t_min >= self.t_max:
            raise ValueError("t_min debe ser menor que t_max")
        return self


DiagramRequest = Annotated[
    FunctionDiagram
    | ForcesDiagram
    | ProjectileDiagram
    | GraphDiagram
    | SurfaceDiagram
    | ContourDiagram
    | VectorFieldDiagram
    | Curve3DDiagram,
    Field(discriminator="kind"),
]


# --- Dibujos a mano ------------------------------------------------------------

MAX_STROKES = 3000
MAX_POINTS_PER_STROKE = 6000
MAX_TOTAL_POINTS = 250_000

HexColor = Annotated[str, StringConstraints(pattern=r"^#[0-9a-fA-F]{6}$")]
CanvasSize = Annotated[float, Field(ge=100, le=10_000, allow_inf_nan=False)]


class Stroke(BaseModel):
    """Trazo: `points` es una lista plana `[x0, y0, p0, x1, y1, p1, ...]` con la
    posición en unidades del lienzo y la presión normalizada (0–1)."""

    tool: Literal["pen", "highlighter"] = "pen"
    color: HexColor = "#1B1F24"
    width: Annotated[float, Field(ge=0.5, le=60, allow_inf_nan=False)] = 3.0
    points: Annotated[
        list[Annotated[float, Field(allow_inf_nan=False)]],
        Field(min_length=3, max_length=MAX_POINTS_PER_STROKE * 3),
    ]

    @model_validator(mode="after")
    def _check_points(self) -> "Stroke":
        if len(self.points) % 3:
            raise ValueError("points debe tener tripletas [x, y, presión]")
        if any(not 0 <= p <= 1 for p in self.points[2::3]):
            raise ValueError("la presión debe estar entre 0 y 1")
        return self


Strokes = Annotated[list[Stroke], Field(max_length=MAX_STROKES)]


def _check_total_points(strokes: list[Stroke]) -> None:
    if sum(len(s.points) for s in strokes) // 3 > MAX_TOTAL_POINTS:
        raise ValueError(f"El dibujo supera {MAX_TOTAL_POINTS} puntos")


class DrawingCreate(BaseModel):
    width: CanvasSize = 1000.0
    height: CanvasSize = 700.0
    strokes: Strokes = []

    @model_validator(mode="after")
    def _check_size(self) -> "DrawingCreate":
        _check_total_points(self.strokes)
        return self


class DrawingUpdate(BaseModel):
    width: CanvasSize | None = None
    height: CanvasSize | None = None
    strokes: Strokes | None = None

    @model_validator(mode="after")
    def _check_size(self) -> "DrawingUpdate":
        if self.strokes is not None:
            _check_total_points(self.strokes)
        return self


class Drawing(BaseModel):
    id: int
    note_id: int
    width: float
    height: float
    strokes: list[Stroke]
    created_at: str
    updated_at: str
