"""Protección del servidor: origen de la conexión y token de acceso.

Dos comprobaciones **independientes**, en este orden:

1. **Origen (403):** solo se aceptan conexiones desde el propio equipo (loopback)
   o desde redes privadas (LAN). Es una defensa adicional para reducir la
   exposición; **no sustituye a la autenticación**: cualquier dispositivo de la
   misma red sigue llegando hasta el paso 2.
2. **Token (401):** toda petición debe llevar `Authorization: Bearer <token>`,
   también las del propio equipo. Solo quedan fuera `/health` (sin datos
   sensibles) y la documentación de la API (el esquema ya es público en el repo).

Sin TLS, el token viaja **sin cifrar** por la red: quien capture el tráfico de la
WiFi puede leerlo. Ver `docs/SERVER_SECURITY.md`.
"""

import ipaddress
import os
import secrets
from collections.abc import Callable
from pathlib import Path

from starlette.types import ASGIApp, Receive, Scope, Send

from app.config import env
from app.errors import error_response

TOKEN_FILE_NAME = "api_token"
TOKEN_HEADER = "authorization"

# Rutas que no exigen token. No devuelven datos del usuario.
PUBLIC_PATHS = frozenset({"/health", "/docs", "/docs/oauth2-redirect", "/openapi.json", "/redoc"})


def load_or_create_token(data_dir: Path) -> str:
    """Token del servidor: `EULER_API_TOKEN` o, si no existe, el guardado en
    `<data_dir>/api_token` (se crea con permisos 0600 la primera vez)."""
    configured = env("API_TOKEN")
    if configured is not None:
        token = configured.strip()
        if len(token) < 16:
            raise ValueError("EULER_API_TOKEN debe tener al menos 16 caracteres")
        return token

    path = data_dir / TOKEN_FILE_NAME
    if path.exists():
        token = path.read_text(encoding="utf-8").strip()
        if token:
            return token

    data_dir.mkdir(parents=True, exist_ok=True)
    token = secrets.token_urlsafe(32)
    try:
        # O_EXCL: si dos procesos arrancan a la vez, el segundo lee el del primero.
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        return path.read_text(encoding="utf-8").strip()
    with os.fdopen(fd, "w", encoding="utf-8") as file:
        file.write(token + "\n")
    return token


class TokenStore:
    """Carga el token la primera vez que se necesita (al arrancar el servidor),
    no al importar el módulo: así importar `app.main` no crea archivos."""

    def __init__(self, data_dir: Callable[[], Path]) -> None:
        self._data_dir = data_dir
        self._token: bytes | None = None

    def get(self) -> bytes:
        if self._token is None:
            self._token = load_or_create_token(self._data_dir()).encode()
        return self._token

    def source(self) -> str:
        """Dónde está el token, para indicarlo en la consola (sin mostrarlo)."""
        if env("API_TOKEN") is not None:
            return "la variable EULER_API_TOKEN"
        return str(self._data_dir() / TOKEN_FILE_NAME)


def allowed_networks() -> list[ipaddress.IPv4Network | ipaddress.IPv6Network]:
    """Redes extra permitidas (`EULER_ALLOWED_NETWORKS`, CIDR separados por comas),
    p. ej. `100.64.0.0/10` para una VPN tipo Tailscale."""
    raw = env("ALLOWED_NETWORKS", "") or ""
    return [
        ipaddress.ip_network(item.strip(), strict=False) for item in raw.split(",") if item.strip()
    ]


def is_allowed_client(
    host: str | None, extra: list[ipaddress.IPv4Network | ipaddress.IPv6Network]
) -> bool:
    """True si la conexión viene del propio equipo, de una red privada o de `extra`."""
    if not host:
        return False
    try:
        address = ipaddress.ip_address(host)
    except ValueError:
        return False
    if isinstance(address, ipaddress.IPv6Address) and address.ipv4_mapped:
        address = address.ipv4_mapped
    if address.is_loopback or address.is_private:
        return True
    return any(address in network for network in extra)


def _bearer(headers: list[tuple[bytes, bytes]]) -> str | None:
    for name, value in headers:
        if name.lower() == TOKEN_HEADER.encode():
            scheme, _, credentials = value.decode("latin-1").partition(" ")
            if scheme.lower() == "bearer" and credentials.strip():
                return credentials.strip()
            return None
    return None


class SecurityMiddleware:
    """Middleware ASGI. Se coloca **dentro** de CORS para que las respuestas 401/403
    lleguen al navegador con sus cabeceras CORS y el preflight `OPTIONS` no
    necesite token."""

    def __init__(self, app: ASGIApp, tokens: TokenStore) -> None:
        self.app = app
        self._tokens = tokens
        self._networks = allowed_networks()

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        client = scope.get("client")
        if not is_allowed_client(client[0] if client else None, self._networks):
            response = error_response(
                403, "forbidden_origin", "Conexión rechazada: solo se aceptan redes locales"
            )
            await response(scope, receive, send)
            return

        if scope["path"] in PUBLIC_PATHS or scope["method"] == "OPTIONS":
            await self.app(scope, receive, send)
            return

        provided = _bearer(scope.get("headers", []))
        if provided is None or not secrets.compare_digest(provided.encode(), self._tokens.get()):
            response = error_response(
                401,
                "unauthorized",
                "Token de acceso incorrecto o ausente. Cópialo del servidor "
                "(backend/data/api_token) en Servidor → Token.",
            )
            response.headers["WWW-Authenticate"] = "Bearer"
            await response(scope, receive, send)
            return

        await self.app(scope, receive, send)
