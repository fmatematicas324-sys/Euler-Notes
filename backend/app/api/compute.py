from fastapi import APIRouter

from app.config import get_compute_timeout
from app.domain.models import ComputeRequest, ComputeResponse
from app.services.compute import run_compute

router = APIRouter(tags=["compute"])


@router.post("/compute")
def compute(body: ComputeRequest) -> ComputeResponse:
    result = run_compute(body.expr, body.op, body.var, get_compute_timeout())
    return ComputeResponse(result_latex=result.latex, result_text=result.text)
