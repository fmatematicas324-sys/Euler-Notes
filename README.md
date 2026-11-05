# Cuaderno Científico

Cuaderno digital para escribir ciencia: notas en Markdown, fórmulas LaTeX y cálculo simbólico.
Multiplataforma con Flutter (prioridad Web y Linux) y backend local en Python (FastAPI + SymPy + SQLite).

## Estructura
- `docs/`: especificación, arquitectura y roadmap.
- `app/`: aplicación Flutter (`core/` + `features/{notebooks,notes,compute}`).
- `backend/`: servicio FastAPI (`api/`, `domain/`, `services/`, `storage/`).

## Entorno de desarrollo
```bash
# Backend
cd backend
python3 -m venv .venv
.venv/bin/pip install -e ".[dev]"

# Flutter (SDK en ~/development/flutter)
export PATH="$HOME/development/flutter/bin:$PATH"
flutter doctor
```

## APK para Android
GitHub Actions compila el APK en cada push que toca `app/` y lo publica en *Releases* (`v0.4.0`).
La app usa el backend de un PC en la misma WiFi:
```bash
cd backend && .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
```
En la app: icono de servidor → `http://IP-DEL-PC:8000`.

Más detalles en [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) y [`docs/ROADMAP.md`](docs/ROADMAP.md).
