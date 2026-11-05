from fastapi import APIRouter

router = APIRouter(tags=["auth"])


@router.get("/auth/check")
def auth_check() -> dict[str, bool]:
    """Responde solo si el token es correcto (lo valida `SecurityMiddleware`).
    La app lo usa en «Probar conexión»."""
    return {"authenticated": True}
