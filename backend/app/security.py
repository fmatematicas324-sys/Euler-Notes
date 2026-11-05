"""Protección del servidor: origen de la conexión y token de acceso.

Dos comprobaciones **independientes**, en este orden:

1. **Origen (403):** solo se aceptan conexiones cuya IP de socket esté en una
   lista explícita (`ALLOWED_NETWORKS`: loopback, RFC 1918, link-local y ULA) y
   fuera de `DENIED_NETWORKS` (Teredo, 6to4, multicast, no especificadas). Se
   rechazan las peticiones con cabeceras de proxy (`X-Forwarded-For`...).
   Es una defensa adicional para reducir la exposición; **no sustituye a la
   autenticación**: cualquier dispositivo de la misma red sigue llegando hasta
   el paso 2.
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


Network = ipaddress.IPv4Network | ipaddress.IPv6Network

# Política explícita (no `ipaddress.is_private`, que también considera "privadas"
# redes enrutables desde Internet como Teredo o 6to4).
ALLOWED_NETWORKS: tuple[Network, ...] = tuple(
    ipaddress.ip_network(cidr)
    for cidr in (
        "127.0.0.0/8",  # loopback IPv4
        "10.0.0.0/8",  # RFC 1918
        "172.16.0.0/12",  # RFC 1918
        "192.168.0.0/16",  # RFC 1918
        "169.254.0.0/16",  # link-local IPv4
        "::1/128",  # loopback IPv6
        "fe80::/10",  # link-local IPv6
        "fc00::/7",  # Unique Local Addresses (ULA)
    )
)

# Siempre rechazadas, aunque aparezcan en `EULER_ALLOWED_NETWORKS`.
DENIED_NETWORKS: tuple[Network, ...] = tuple(
    ipaddress.ip_network(cidr)
    for cidr in (
        "0.0.0.0/8",  # "esta red" / no especificada
        "224.0.0.0/4",  # multicast IPv4
        "255.255.255.255/32",  # broadcast
        "::/128",  # no especificada IPv6
        "ff00::/8",  # multicast IPv6
        "2001::/32",  # Teredo (túnel enrutable desde Internet)
        "2002::/16",  # 6to4 (túnel enrutable desde Internet)
    )
)

# Cabeceras con las que un cliente o un proxy declara otro origen. No se usan
# para decidir: si llegan, la petición se rechaza (ver `SecurityMiddleware`).
FORWARDING_HEADERS = frozenset({b"x-forwarded-for", b"forwarded", b"x-real-ip"})


def allowed_networks() -> list[Network]:
    """Redes extra permitidas (`EULER_ALLOWED_NETWORKS`, CIDR separados por comas),
    p. ej. `100.64.0.0/10` para una VPN tipo Tailscale. `DENIED_NETWORKS` sigue
    teniendo prioridad."""
    raw = env("ALLOWED_NETWORKS", "") or ""
    return [
        ipaddress.ip_network(item.strip(), strict=False) for item in raw.split(",") if item.strip()
    ]


def is_allowed_client(host: str | None, extra: list[Network]) -> bool:
    """True solo si la IP del socket pertenece a `ALLOWED_NETWORKS` o a `extra`,
    y no a `DENIED_NETWORKS`. Las direcciones IPv4-mapped (`::ffff:a.b.c.d`) se
    evalúan como la IPv4 que contienen."""
    if not host:
        return False
    try:
        address = ipaddress.ip_address(host)
    except ValueError:
        return False
    if isinstance(address, ipaddress.IPv6Address) and address.ipv4_mapped is not None:
        address = address.ipv4_mapped
    if any(address in network for network in DENIED_NETWORKS):
        return False
    return any(address in network for network in (*ALLOWED_NETWORKS, *extra))


def has_forwarding_headers(headers: list[tuple[bytes, bytes]]) -> bool:
    return any(name.lower() in FORWARDING_HEADERS for name, _ in headers)


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

        # El origen se decide solo con la IP del socket. Si llegan cabeceras de
        # proxy, se rechaza: uvicorn (con `--proxy-headers`, activo por defecto)
        # reescribe `client` a partir de ellas cuando la conexión viene de
        # 127.0.0.1, y aquí ya no se puede saber cuál era el socket real.
        if has_forwarding_headers(scope.get("headers", [])):
            response = error_response(
                403,
                "forwarded_not_allowed",
                "Conexión rechazada: no se admiten peticiones reenviadas por un proxy",
            )
            await response(scope, receive, send)
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
