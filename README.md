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

Más detalles en [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) y [`docs/ROADMAP.md`](docs/ROADMAP.md).
