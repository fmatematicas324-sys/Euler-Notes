from fastapi import APIRouter, Response

from app.config import get_compute_timeout
from app.domain.models import PlotRequest
from app.services.compute import run_plot
from app.services.plotting import PlotSpec

router = APIRouter(tags=["plot"])


@router.post(
    "/plot",
    response_class=Response,
    responses={200: {"content": {"image/png": {}}, "description": "Gráfica PNG transparente"}},
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
