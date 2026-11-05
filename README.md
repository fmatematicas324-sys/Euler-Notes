# Euler Notes — Cuaderno Científico

Cuaderno científico para Física y Matemáticas: notas en Markdown, fórmulas LaTeX y cálculo simbólico.
Multiplataforma con Flutter (prioridad tablet Android; también Linux y Web) y backend local en Python (FastAPI + SymPy + SQLite).

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

## Versiones
La fuente única es `app/pubspec.yaml` (`version: X.Y.Z+N`): `X.Y.Z` con versionado semántico y `N` = número de compilación (versionCode de Android), que sube en cada release y nunca se reutiliza. `backend/pyproject.toml` lleva la misma `X.Y.Z`; `python3 tool/check_versions.py` lo comprueba (también en CI). Cambios: [`docs/CHANGELOG.md`](docs/CHANGELOG.md).

## APK para Android
GitHub Actions (`ci.yml`) compila un APK de comprobación en cada push (artefacto de 7 días). Las releases solo se crean al subir un tag `vX.Y.Z`, como **borrador** (`release.yml`).
La app usa el backend de un PC en la misma WiFi:
```bash
cd backend && .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
cat data/api_token   # token de acceso (se crea en el primer arranque)
```
En la app: icono de servidor → `http://IP-DEL-PC:8000` y el token. **Sin HTTPS, el token viaja sin cifrar**: usa solo redes de confianza. Detalles en [`docs/SERVER_SECURITY.md`](docs/SERVER_SECURITY.md).

Más detalles en [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) y [`docs/ROADMAP.md`](docs/ROADMAP.md).
