from typing import Annotated

from fastapi import APIRouter, Body, Response

from app.config import get_compute_timeout
from app.domain.models import DiagramRequest, PlotRequest
from app.services.compute import run_diagram, run_plot
from app.services.plotting import PlotSpec

router = APIRouter(tags=["plot"])
_PNG = {200: {"content": {"image/png": {}}, "description": "Imagen PNG transparente"}}


@router.post(
    "/plot",
    response_class=Response,
    responses=_PNG,
)
def plot(body: PlotRequest) -> Response:
    spec = PlotSpec(
        exprs=tuple(body.exprs),
        var=body.var,
        x_min=body.x_min,
        x_max=body.x_max,
        y_min=body.y_min,
        y_max=body.y_max,
        theme=body.theme,
        width=body.width,
        height=body.height,
        scale=body.scale,
    )
    png = run_plot(spec, get_compute_timeout())
    return Response(content=png, media_type="image/png")


@router.post("/diagram", response_class=Response, responses=_PNG)
def diagram(body: Annotated[DiagramRequest, Body()]) -> Response:
    """Diagramas científicos: `function` (análisis de la operación de /compute),
    `forces` (cuerpo libre), `projectile` (tiro parabólico) y `graph` (NetworkX)."""
    png = run_diagram(body.model_dump(), get_compute_timeout())
    return Response(content=png, media_type="image/png")
