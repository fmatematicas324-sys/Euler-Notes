# Cuaderno Científico — Registro de desarrollo

Registro cronológico de lo construido, las decisiones tomadas y el estado de la verificación.

---

## 2026-11-03 — Fase 0: Cimientos ✅

| Commit | Contenido |
|---|---|
| `a23b76e` | `docs/` (PRODUCT_SPEC, ARCHITECTURE, ROADMAP), esqueleto `app/` + `backend/`, `.gitignore`, `README.md`, `backend/pyproject.toml` |
| `098321c` | Roadmap: Flutter SDK instalado |

**Entorno**
- Flutter stable **3.47.9** (Dart 3.13.7) en `~/development/flutter`, con web y linux-desktop activados.
- Paquetes del sistema (Fedora 44): `clang`, `cmake`, `ninja-build`, `gtk3-devel`, `chromium`, `mesa-demos`.
- `~/.bashrc`: `flutter` añadido al `PATH` y `CHROME_EXECUTABLE` apuntando a Chromium.
- Python 3.14.8 con venv en `backend/.venv`: fastapi 0.162, uvicorn, sympy 1.14, pytest, httpx, ruff 0.17.
- `flutter doctor`: ✓ Flutter, ✓ Chrome, ✓ Linux toolchain. Android ✗, previsto para la Fase 3. Queda un aviso menor de `eglinfo` que no bloquea.

---

## 2026-11-03 — Fase 1 (parte backend + base Flutter)

### 1. Servidor base FastAPI — `032c364`
- `backend/app/main.py`: `create_app()` con *lifespan*, CORS limitado a `localhost`/`127.0.0.1` y routers.
- `backend/app/errors.py`: formato único `{"error": {"code", "message"}}` para errores propios, de validación (422) y HTTP (404...).
- `backend/app/config.py`: `CUADERNO_DB_PATH` y `CUADERNO_COMPUTE_TIMEOUT`.
- `GET /health` → `{"status": "ok", "version": "0.1.0"}`.

### 2. SQLite + CRUD — `82a4949`
- `storage/schema.sql` idempotente; `notes.notebook_id` con `ON DELETE CASCADE` y `PRAGMA foreign_keys = ON`.
- `storage/db.py`: una conexión por petición (dependencia FastAPI), con commit o rollback automático.
- `storage/repository.py`: funciones puras sobre la conexión, sin ORM.
- Endpoints: `/notebooks` (GET, POST), `/notebooks/{id}` (GET, PUT, DELETE), `/notebooks/{id}/notes` (GET resumen, POST), `/notes/{id}` (GET, PUT parcial, DELETE).
- Se añadió `GET /notebooks/{id}`, que no estaba en el contrato inicial; ARCHITECTURE.md ya está actualizado.

### 3. Cálculo simbólico — `7801e7a`
- `services/sympy_engine.py`: validación por capas (caracteres permitidos, punto solo decimal, sin palabras clave de Python, longitud) y luego `parse_expr` con un `global_dict` mínimo y `__builtins__` vacío.
- `services/compute.py`: cada cálculo corre en un subproceso **forkserver** con SymPy precargado, con *timeout* (408) y límite de 1 GiB de memoria.
- `POST /compute`: `simplify`, `diff`, `integrate`, `solve` (admite `lhs = rhs`).
- Verificado con uvicorn real: `/health`, CRUD, `/compute` (criterio de aceptación 3), rechazo de `__import__` y `/docs` (200).

### 4. Base Flutter — `2e086e2`
- `flutter create --platforms web,linux` en `app/` (org `dev.cuadernocientifico`).
- Dependencias: `flutter_riverpod` 3.4, `http` 1.6, `flutter_markdown_plus` 1.0, `flutter_math_fork` 0.7. Se quitó `cupertino_icons`.
- `lib/core/`: `config.dart` (`API_BASE_URL` por `--dart-define`), `api_client.dart` (traduce el formato de error a `ApiException`), `theme.dart` (Material 3 claro y oscuro), `backend_health.dart`.
- `HomeScreen` provisional: muestra si el backend está conectado y ofrece "Reintentar".
- Web: título "Cuaderno Científico" y `lang="es"`.

### Estado de la verificación
| Comprobación | Resultado |
|---|---|
| `pytest` (backend) | **54 passed** |
| `ruff check` + `ruff format --check` | OK |
| `flutter analyze` | No issues found |
| `flutter test` | **7 passed** |
| `flutter build web` | ✓ |
| `flutter build linux` | ✓ |

### Decisiones y notas
- **forkserver en lugar de fork**: el servidor usa hilos (threadpool de FastAPI) y hacer `fork` con hilos es inseguro. Con SymPy precargado, el primer cálculo tarda unos 1,7 s (arranque del servidor de procesos) y los siguientes unos 0,3 s.
- **Multiplicación implícita**: `2x` se lee como `2*x`. Como efecto, `f(x)` con un nombre desconocido se lee como `f*x`; es inofensivo y está cubierto por un test.
- **Aviso de Starlette**: `TestClient` muestra un aviso de deprecación de `httpx` (recomienda `httpx2`). No afecta a los tests; se revisará al actualizar dependencias.
- **Primera compilación web**: tardó unos 4 min; las siguientes usan caché.

### Pendiente en la Fase 1
- Pantalla de cuadernos (listar, crear, renombrar, eliminar).
- Pantalla de notas de un cuaderno.
- Editor dividido Markdown con vista previa LaTeX.
- Panel de cálculo con inserción del resultado en la nota.
- Prueba manual de aceptación en Chrome y Linux (PRODUCT_SPEC §5).

### Cómo ejecutar
```bash
# Backend
cd backend && .venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000
.venv/bin/pytest

# App (con el backend arrancado)
cd app && flutter run -d chrome    # o -d linux
flutter analyze && flutter test
```
