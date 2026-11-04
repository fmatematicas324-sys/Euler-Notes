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
└──────────────────────────┘                │  SymPy+matplotlib  SQLite    │
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
    │   ├── services/         # motor SymPy, gráficas, sandbox (subproceso aislado)
    │   └── storage/          # repositorios SQLite (sqlite3 de la stdlib)
    └── tests/
```

### Capas en Flutter (por feature)
- `data/`: llamadas HTTP y mapeo JSON ⇄ modelos.
- `domain/`: modelos inmutables y contratos de repositorio.
- `presentation/`: widgets, pantallas y providers de Riverpod.

`core/` no depende de ninguna feature. Una feature solo puede importar la capa `presentation/` de otra, y solo para navegar o componer pantallas (p. ej. `notebooks` abre `NotebookScreen` pasando `id` y título; el editor de `notes` incluye `ComputePanel`). Nunca importa su `data/` ni su `domain/`. Lo compartido va a `core/`, como `MathFormula`, los diálogos o `ApiClient`.

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
- `schema.sql` (v0.1) es idempotente. A partir de él, las **migraciones versionadas** de `storage/db.py` (`PRAGMA user_version`) añaden cambios sin perder datos. v0.2: `notebooks.cover`, `notes.paper` y la tabla `documents` (`id, filename, size, pages, created_at`).
- Los PDF se guardan en `data/documents/{id}.pdf`, junto a la base de datos.
- `cover` y `paper` son identificadores (`^[a-z][a-z0-9_]{0,31}$`): el catálogo vive en la app y un valor desconocido se muestra con el valor por defecto.

## 4. Contrato de la API (v0.2)
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
| POST | `/plot` | `{exprs[1..5], var?, x_min?, x_max?, y_min?, y_max?, theme?, width?, height?, scale?}` → PNG transparente (`image/png`) |
| POST | `/diagram` | `{kind: function\|forces\|projectile\|graph, …, theme?, width?, height?, scale?}` → PNG |
| GET | `/documents` | → `[Document]` |
| POST | `/documents?filename=` | PDF en bruto (`application/pdf`, máx. 30 MB) → `Document` (201) |
| GET | `/documents/{id}` | → `Document` |
| GET | `/documents/{id}/file` | → PDF |
| GET | `/documents/{id}/pages/{n}/text` | → `{page, text, latex}` |
| DELETE | `/documents/{id}` | → 204 |
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
- **Tiempo máximo de 5 s** por operación (`CUADERNO_COMPUTE_TIMEOUT`). `/compute` y `/plot` se ejecutan en `services/sandbox.py`: un subproceso nacido de un `forkserver` con SymPy, numpy y matplotlib precargados (y con matplotlib ya calentado), con **1 GiB** de memoria máxima (`RLIMIT_AS`). Si se pasa del tiempo se mata (error 408). El forkserver arranca en segundo plano al iniciar el servidor (unos 3–4 s).
- `/plot` valida cada expresión igual que `/compute`, exige que solo dependa de la variable y evalúa con `lambdify` sobre numpy (o punto a punto con mpmath cuando no hay versión vectorizada). Corta las asíntotas, se queda solo con los valores reales y, si no se indica el rango de `y`, lo calcula por percentiles. Usa `Figure` + Agg, sin `pyplot` ni estado global.
- Los nombres desconocidos (p. ej. `eval`, `system`) se convierten en símbolos inertes de SymPy; nunca se resuelven a funciones de Python.
- CORS: solo orígenes `http://localhost:*` y `http://127.0.0.1:*`. El servidor escucha solo en `127.0.0.1`.

## 6. Interfaz y renderizado en Flutter
- **Pantallas:** `NotebooksScreen` → `NotebookScreen` → `NoteEditorScreen`, con `Navigator` y `MaterialPageRoute`.
- **Estado:** `AsyncNotifier` de Riverpod por lista (cuadernos; notas por cuaderno con `family`). Después de cada cambio se recarga desde el backend, que es la fuente de verdad.
- **Editor:** con ancho ≥ 840 px, texto y vista previa van lado a lado; con menos, en pestañas. Guarda solo tras 800 ms sin escribir, con Ctrl+S y al salir; si falla, pregunta antes de salir.
- **Markdown:** `flutter_markdown_plus` (GFM) con dos sintaxis propias:
  - `MathInlineSyntax`: `$...$` en línea (sin espacio junto a los `$`, para no confundir precios) y `$$...$$` dentro de un párrafo.
  - `MathBlockSyntax`: `$$...$$` en una línea propia o en varias; se muestra como bloque centrado.
- **LaTeX:** `flutter_math_fork` mediante `core/widgets/math_formula.dart`. Si una fórmula es inválida, se muestra el texto fuente en rojo y la app no se cae.
- **Cálculo:** `ComputePanel` en un *bottom sheet*. Inserta el resultado en el cursor como `$...$` o como bloque `$$...$$` en una línea propia.
- **Gráficas:** un bloque ` ```plot ` (una expresión por línea; opciones `x: -2pi, 2pi`, `y: a, b` y `var: t`) se muestra con `PlotView` (`features/plot`). `PlotView` pide el PNG con el ancho disponible (en saltos de 50 px), el tema y la densidad de píxeles; espera 400 ms mientras se escribe, mantiene la imagen anterior y ofrece «Reintentar» si falla. `PlotRepository` guarda en caché las últimas 32 imágenes.
- **Diagramas:** un bloque ` ```diagram ` (`tipo: funcion | fuerzas | proyectil | grafo`, ver `DiagramSpec.parse`) se muestra con el mismo `FigureView`. `PlotSpec` y `DiagramSpec` implementan `FigureSpec`, que indica el endpoint y el cuerpo de la petición.
- **Teclado de símbolos** (`features/symbols`): catálogo de LaTeX con marca de cursor (`‸`). Fuera de una fórmula se envuelve en `$…$`, o en `$$…$$` para las matrices.
- **PDF** (`features/documents`): biblioteca en una hoja inferior y visor pdfrx con el texto de la página («Texto» → cita con la fuente; «LaTeX» → fórmula). El selector de archivos y el visor se inyectan por providers para poder probarlos sin pdfium.
- **Estantería:** cuadrícula de `NotebookCoverCard` (portada, lomo, etiqueta y repisa) con 8 portadas `CustomPainter`.
- **Papel:** `PaperBackground` detrás del editor (renglonado alineado a su altura de línea) y de la vista previa. El milimetrado usa 1 mm ≈ 3,78 px lógicos.

## 7. Dependencias
**Backend:** `fastapi`, `uvicorn`, `sympy`, `matplotlib` + `numpy` (v0.2, gráficas) · *dev:* `pytest`, `httpx`, `ruff`.
**Backend v0.2:** `networkx` (grafos), `pypdf` (PDF).
**App:** `flutter_riverpod`, `http`, `flutter_markdown_plus`, `markdown`, `flutter_math_fork`, `pdfrx` (visor de PDF), `file_selector` (importar archivos) · *dev:* `flutter_lints`, `flutter_test`, `integration_test`.

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
| 6 | Los PDF se analizan en el subproceso aislado | Son archivos no confiables: pypdf puede tardar o consumir mucha memoria con PDF malformados. |
| 7 | Portadas, papel e icono dibujados con `CustomPainter` | No hacen falta imágenes ni derechos de terceros; escalan a cualquier densidad y siguen el tema claro u oscuro. |
| 5 | Gráficas renderizadas en el backend (matplotlib → PNG), no en Flutter | Reutiliza la evaluación segura de SymPy y la calidad de matplotlib; el cliente solo muestra una imagen. A cambio, hace falta el backend (ver la decisión pendiente sobre Android en el ROADMAP). |
