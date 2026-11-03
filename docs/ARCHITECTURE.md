# Cuaderno Científico — Arquitectura

> Versión del documento: v0.1 · Estado: borrador aprobado (Fase 0)

## 1. Visión general
Son dos procesos locales: no hay microservicios ni infraestructura externa.

```
┌──────────────────────────┐   HTTP/JSON    ┌──────────────────────────────┐
│  app/  (Flutter)         │  localhost     │  backend/  (Python FastAPI)  │
│  Web · Linux (· Mobile)  │ ─────────────▶ │                              │
│                          │ ◀───────────── │  api → services → storage    │
│  UI, Markdown, LaTeX     │                │            │          │      │
└──────────────────────────┘                │         SymPy     SQLite     │
                                            └──────────────────────────────┘
```

- **Flutter** se encarga de la interfaz, la edición y el renderizado (Markdown + LaTeX).
- **FastAPI** se encarga de la persistencia y el cálculo simbólico.
- Comunicación REST/JSON en `http://127.0.0.1:8000` (configurable).

## 2. Estructura de carpetas
```
CUADERNO_CIENTIFICO/
├── docs/
├── app/                      # Flutter
│   ├── lib/
│   │   ├── main.dart
│   │   ├── core/             # api_client, config, theme, errores comunes
│   │   └── features/
│   │       ├── notebooks/    # data / domain / presentation
│   │       ├── notes/        # data / domain / presentation
│   │       └── compute/      # data / domain / presentation
│   └── test/
└── backend/                  # Python
    ├── pyproject.toml
    ├── app/
    │   ├── main.py           # crea la app FastAPI, CORS, routers
    │   ├── api/              # routers HTTP (sin lógica de negocio)
    │   ├── domain/           # modelos Pydantic (entrada/salida)
    │   ├── services/         # lógica de negocio + motor SymPy
    │   └── storage/          # repositorios SQLite (sqlite3 de la stdlib)
    └── tests/
```

### Capas en Flutter (por feature)
- `data/`: llamadas HTTP y mapeo JSON ⇄ modelos.
- `domain/`: modelos inmutables y contratos de repositorio.
- `presentation/`: widgets, pantallas y providers de Riverpod.

`core/` no depende de ninguna feature, y una feature no importa a otra; si necesitan compartir algo, eso va a `core/`.

### Capas en backend
`api` → `services` → `storage`. Cada capa solo llama a la de abajo. `domain` lo usan todas.

## 3. Modelo de datos
```
Notebook                      Note
─────────────────────         ─────────────────────────────
id          INTEGER PK        id           INTEGER PK
title       TEXT NOT NULL     notebook_id  INTEGER FK → Notebook.id (ON DELETE CASCADE)
created_at  TEXT (ISO 8601)   title        TEXT NOT NULL
updated_at  TEXT (ISO 8601)   content      TEXT  (Markdown + LaTeX)
                              created_at   TEXT
                              updated_at   TEXT
```
- Archivo: `backend/data/cuaderno.db` (ignorado por git; la ruta se puede cambiar con la variable `CUADERNO_DB_PATH`).
- Las migraciones de v0.1 son un script `schema.sql` idempotente (`CREATE TABLE IF NOT EXISTS`) que se aplica al arrancar.

## 4. Contrato de la API (v0.1)
| Método | Ruta | Cuerpo / respuesta |
|---|---|---|
| GET | `/notebooks` | → `[Notebook]` |
| POST | `/notebooks` | `{title}` → `Notebook` (201) |
| GET | `/notebooks/{id}` | → `Notebook` |
| PUT | `/notebooks/{id}` | `{title}` → `Notebook` |
| DELETE | `/notebooks/{id}` | → 204 |
| GET | `/notebooks/{id}/notes` | → `[NoteSummary]` (sin `content`) |
| POST | `/notebooks/{id}/notes` | `{title, content?}` → `Note` (201) |
| GET | `/notes/{id}` | → `Note` |
| PUT | `/notes/{id}` | `{title?, content?}` → `Note` |
| DELETE | `/notes/{id}` | → 204 |
| POST | `/compute` | `{expr, op, var?}` → `{result_latex, result_text}` |
| GET | `/health` | → `{status: "ok", version}` |

- `op` ∈ `simplify | diff | integrate | solve`. `var` es opcional (por defecto `x`).
- `solve` admite `"lhs = rhs"` o una expresión igualada a 0. Multiplicación implícita activa (`2x` = `2*x`).
- Formato de error único: `{"error": {"code": "...", "message": "..."}}`.

| HTTP | `code` | Cuándo |
|---|---|---|
| 400 | `invalid_expression` | Expresión no permitida o con sintaxis inválida |
| 404 | `not_found` | Cuaderno, nota o ruta inexistente |
| 408 | `compute_timeout` | El cálculo superó el tiempo máximo |
| 422 | `validation_error` | Cuerpo de la petición inválido (campos, longitudes, `op`, `var`) |
| 422 | `compute_error` | SymPy no pudo calcular (o se superó el límite de memoria) |

## 5. Seguridad del motor de cálculo
- **Nunca** se usan `eval`/`exec` ni `sympify` sobre texto sin filtrar.
- Se usa `sympy.parsing.sympy_parser.parse_expr` con:
  - `global_dict` limitado a una **lista blanca** de símbolos y funciones (`sin, cos, tan, exp, log, sqrt, pi, E, Abs, ...`);
  - `local_dict` vacío y transformaciones estándar (más multiplicación implícita).
- Se rechaza antes de interpretar: longitud > 500 caracteres, `__`, `import`, `lambda`, `;`, corchetes de indexación y atributos (`.`) que no formen parte de un número.
- **Tiempo máximo de 5 s** por operación (`CUADERNO_COMPUTE_TIMEOUT`): el cálculo corre en un subproceso `forkserver` con SymPy precargado y **1 GiB** de memoria máxima (`RLIMIT_AS`); si se pasa del tiempo se mata (error 408).
- Los nombres desconocidos (p. ej. `eval`, `system`) se convierten en símbolos inertes de SymPy; nunca se resuelven a funciones de Python.
- CORS: solo orígenes `http://localhost:*` y `http://127.0.0.1:*`. El servidor escucha solo en `127.0.0.1`.

## 6. Renderizado en Flutter
- Markdown con `flutter_markdown_plus`.
- LaTeX con `flutter_math_fork`, mediante sintaxis personalizada (inline `$...$` y bloque `$$...$$`) conectada al parser Markdown.
- Si una fórmula es inválida, se muestra el texto fuente en rojo y la app no se cae.

## 7. Dependencias mínimas v0.1
**Backend:** `fastapi`, `uvicorn`, `sympy` · *dev:* `pytest`, `httpx`, `ruff`.
**App:** `flutter_riverpod`, `http`, `flutter_markdown_plus`, `flutter_math_fork` · *dev:* `flutter_lints`, `flutter_test`.

Descartados a propósito en v0.1: ORM, router de navegación, Docker y generación de código (freezed/json_serializable).

## 8. Convenciones
- **Código:** identificadores en inglés; textos de la interfaz y documentación en español.
- **Python:** 3.12+, tipado obligatorio, `ruff` para lint y formato.
- **Dart:** `flutter_lints`, `dart format`.
- **Git:** Conventional Commits (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`).
- **Tests:** todo endpoint y servicio nuevo lleva su test; una tarea no está terminada sin `pytest` y `flutter analyze/test` en verde.

## 9. Decisiones de arquitectura (ADR resumidas)
| # | Decisión | Motivo |
|---|---|---|
| 1 | Backend Python local en lugar de solo Dart | SymPy no tiene equivalente maduro en Dart. |
| 2 | SQLite con `sqlite3` de la stdlib, sin ORM | Modelo de 2 tablas; un ORM no compensa. |
| 3 | REST/JSON en lugar de FFI o Python embebido | Funciona igual en Web y Linux, y se puede depurar con `/docs`. |
| 4 | Riverpod para el estado | Estándar, testeable, sin generación de código. |
