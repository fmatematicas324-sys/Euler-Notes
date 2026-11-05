#!/usr/bin/env bash
# Instala el backend de Euler Notes como servicio de usuario de systemd: arranca
# solo al iniciar sesión y se reinicia si se cae. No necesita sudo.
#
#   tool/install_service.sh            # instalar y arrancar
#   tool/install_service.sh --quitar   # parar y desinstalar
#
# Comandos útiles después:
#   systemctl --user status euler-notes      # ¿está corriendo?
#   systemctl --user restart euler-notes     # reiniciar (p. ej. tras git pull)
#   journalctl --user -u euler-notes -f      # ver los registros en vivo
set -euo pipefail

SERVICE=euler-notes
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
UNIT_FILE="$UNIT_DIR/$SERVICE.service"
BACKEND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../backend" && pwd)"
PORT="${EULER_PORT:-8000}"

if [[ "${1:-}" == "--quitar" ]]; then
    systemctl --user disable --now "$SERVICE" 2>/dev/null || true
    rm -f "$UNIT_FILE"
    systemctl --user daemon-reload
    echo "Servicio $SERVICE desinstalado."
    exit 0
fi

if [[ ! -x "$BACKEND_DIR/.venv/bin/uvicorn" ]]; then
    echo "No encuentro $BACKEND_DIR/.venv/bin/uvicorn. Crea el entorno primero (ver README)." >&2
    exit 1
fi

if command -v ss >/dev/null && ss -ltn "sport = :$PORT" | grep -q LISTEN; then
    if ! systemctl --user is-active --quiet "$SERVICE"; then
        echo "El puerto $PORT ya está en uso (¿un uvicorn abierto a mano?). Ciérralo con Ctrl+C y repite." >&2
        exit 1
    fi
fi

mkdir -p "$UNIT_DIR"
cat > "$UNIT_FILE" <<EOF
[Unit]
Description=Euler Notes — backend (FastAPI + SymPy)
After=network-online.target
Wants=network-online.target

[Service]
WorkingDirectory=$BACKEND_DIR
ExecStart=$BACKEND_DIR/.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port $PORT --no-proxy-headers
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now "$SERVICE"
sleep 2
systemctl --user --no-pager --lines=5 status "$SERVICE" || true
echo
echo "Listo. Para conectar la tablet: cd $BACKEND_DIR && .venv/bin/python -m app.pair"
echo "Para que arranque aunque no inicies sesión: loginctl enable-linger \"$USER\""
