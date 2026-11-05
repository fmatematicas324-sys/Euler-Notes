"""Emparejar la tablet con este servidor.

    .venv/bin/python -m app.pair            # dirección y token (con QR)
    .venv/bin/python -m app.pair --rotar    # genera un token nuevo (reinicia el servidor)
    .venv/bin/python -m app.pair --sin-qr   # solo texto

El token se muestra solo cuando se pide en la terminal, nunca en los registros
del servidor: con systemd quedaría guardado en el journal. El QR contiene solo
el token; escanéalo con la cámara de la tablet, cópialo y pégalo en
Servidor → Token.
"""

import argparse
import io
import socket
import sys
from pathlib import Path

from app.config import env, get_db_path
from app.security import TOKEN_FILE_NAME, load_or_create_token

DEFAULT_PORT = 8000


def lan_address() -> str:
    """IP de este equipo en la red local. Un `connect` UDP no envía paquetes:
    solo pide al sistema qué interfaz usaría para salir."""
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        try:
            probe.connect(("10.255.255.255", 1))
            return probe.getsockname()[0]
        except OSError:
            return "127.0.0.1"


def qr_text(data: str) -> str | None:
    """QR en caracteres de bloque para la terminal, o None si falta `segno`."""
    try:
        import segno  # opcional: sin él se muestra solo el texto
    except ImportError:
        return None
    buffer = io.StringIO()
    segno.make(data, error="m").terminal(out=buffer, compact=True)
    return buffer.getvalue()


def rotate_token(data_dir: Path) -> str:
    """Borra el token guardado y crea otro. Lanza RuntimeError si el token
    viene de `EULER_API_TOKEN` (habría que cambiar la variable)."""
    if env("API_TOKEN") is not None:
        raise RuntimeError(
            "El token viene de la variable EULER_API_TOKEN; cámbiala tú y reinicia el servidor"
        )
    (data_dir / TOKEN_FILE_NAME).unlink(missing_ok=True)
    return load_or_create_token(data_dir)


def render(url: str, token: str, *, with_qr: bool = True) -> str:
    lines = [
        "",
        "Euler Notes — datos para la tablet (Servidor)",
        "",
        f"  Dirección:  {url}",
        f"  Token:      {token}",
        "",
    ]
    qr = qr_text(token) if with_qr else None
    if qr:
        lines += ["  Escanea el token con la cámara de la tablet y cópialo:", "", qr]
    elif with_qr:
        lines += ["  (Para ver el QR instala segno: .venv/bin/pip install -e .)", ""]
    lines.append("No compartas el token: quien lo tenga puede leer y cambiar tus notas.")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="python -m app.pair", description="Emparejar la tablet con este servidor."
    )
    parser.add_argument("--rotar", action="store_true", help="genera un token nuevo")
    parser.add_argument("--sin-qr", action="store_true", help="no dibuja el código QR")
    parser.add_argument("--puerto", type=int, default=DEFAULT_PORT, help="puerto del servidor")
    args = parser.parse_args(argv)

    data_dir = get_db_path().parent
    if args.rotar:
        try:
            token = rotate_token(data_dir)
        except RuntimeError as exc:
            print(exc, file=sys.stderr)
            return 1
        print("Token nuevo creado. Reinicia el servidor para que lo use.")
    else:
        token = load_or_create_token(data_dir)

    url = f"http://{lan_address()}:{args.puerto}"
    print(render(url, token, with_qr=not args.sin_qr))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
