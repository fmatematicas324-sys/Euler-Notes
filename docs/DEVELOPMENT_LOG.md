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

---

## 2026-11-03 — Fase 1 (interfaz gráfica v0.1) ✅

| Commit | Contenido |
|---|---|
| `fcb4030` | Widgets comunes (`core/widgets/`) y panel de cálculo (`features/compute`) |
| `103f07e` | Pantallas de cuadernos y notas, editor Markdown con LaTeX, 25 tests de widgets |
| `3ae4cc3` | Prueba de punta a punta (`integration_test/`) contra el backend real |

### Qué hace la app
1. **Cuadernos** (`NotebooksScreen`): listar (más recientes primero), crear, renombrar y eliminar (con confirmación; borra también sus notas). Icono del estado del backend en la AppBar.
2. **Cuaderno** (`NotebookScreen`): lista de notas, crear (abre el editor directamente) y eliminar.
3. **Editor** (`NoteEditorScreen`):
   - Markdown con vista previa en vivo: lado a lado con ≥ 840 px; pestañas *Editar / Vista previa* en pantallas estrechas.
   - Fórmulas nativas: `$...$` en línea y `$$...$$` en bloque. El LaTeX inválido se muestra en rojo sin romper la vista previa.
   - Botones `$ $ Fórmula` y `$$ Bloque`, que envuelven la selección.
   - Guardado automático (800 ms tras dejar de escribir), Ctrl+S y guardado al salir, con indicador *Guardado / Sin guardar / Guardando… / Error al guardar*.
4. **Panel de cálculo**: expresión, operación (Simplificar, Derivar, Integrar, Resolver) y variable. Muestra el resultado en LaTeX y en texto, y permite **insertarlo en línea o como bloque** en la posición del cursor. Los errores del backend se ven en el panel.

### Verificación
| Comprobación | Resultado |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` (widgets + ApiClient) | **25 passed** |
| `flutter test integration_test -d linux` (app real + backend real) | **1 passed**: cuaderno → nota → Markdown/LaTeX → cálculo SymPy → insertar → guardado → reabrir → eliminar |
| `flutter run -d chrome --release` | La app carga en Chromium, conecta con el backend (`GET /health`, `GET /notebooks` = 200) y muestra los cuadernos |
| Preflight CORS desde `http://localhost:8090` | 200 con `access-control-allow-origin` correcto |

Criterios de aceptación de PRODUCT_SPEC §5:
- **1–4:** cumplidos. Están cubiertos por la prueba de punta a punta (persistencia, LaTeX, `diff(sin(x)*x)`) y por los tests del backend (expresiones maliciosas).
- **5:** Linux verificado de punta a punta. Web verificado al cargar y conectar con datos reales; el flujo interactivo en Chrome no está automatizado porque falta `chromedriver`. Para hacerlo a mano, sigue *Cómo ejecutar*.

### Incidencias y decisiones
- **`flutter run -d chrome` en modo debug falló:** la herramienta de depuración de Flutter no se conectó a Chromium en 5 s (*TimeoutException en WebkitDebugger.enable*). Es un fallo de la herramienta de depuración, no de la app; en modo `--release` arranca bien. Si se repite, se puede usar `flutter run -d web-server` y abrir la URL a mano.
- **Puerto 8000 ocupado** en esta máquina por otro proceso que no se pudo identificar (no responde a `/health`). Las pruebas usaron el backend en el **8001**, con `--dart-define=API_BASE_URL=http://127.0.0.1:8001`.
- **Fórmulas:** solo heredan el tamaño y el color del texto que las rodea; antes, un título en negrita las ponía en negrita. Las fórmulas en bloque se muestran un 30 % más grandes que el texto.
- **Regla de imports entre features** aclarada en ARCHITECTURE §2: se permite usar la capa `presentation/` de otra feature para navegar o componer pantallas.
- **Tests:** usan `FakeBackend` (`test/support/fake_backend.dart`), un `MockClient` en memoria con el mismo contrato que el backend, así que también prueban los repositorios y `ApiClient`.

### Cómo ejecutar
```bash
# Terminal 1: backend (usa otro puerto si el 8000 está ocupado)
cd backend && .venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8001

# Terminal 2: app
cd app
flutter run -d chrome --release --dart-define=API_BASE_URL=http://127.0.0.1:8001
flutter run -d linux --dart-define=API_BASE_URL=http://127.0.0.1:8001

# Prueba de punta a punta (con el backend arrancado)
flutter test integration_test -d linux --dart-define=API_BASE_URL=http://127.0.0.1:8001
```

### Siguiente (Fase 2, v0.2)
- Gráficas 2D de funciones, exportar a Markdown y PDF, búsqueda en notas.
- Pendientes menores de v0.1: probar el flujo en Chrome con `chromedriver` y etiquetar `v0.1.0`.

---

## 2026-11-03 — Fase 2 (v0.2), parte 1: gráficas 2D ✅

| Commit | Contenido |
|---|---|
| `f7d61a1` | ROADMAP: v0.2 (gráficas + PDF), v0.3 (stylus con presión) y v0.4 (teclado científico + APK para tablet), orientadas a Android, más la decisión pendiente sobre el backend en Android |
| `43bde6c` | Backend: `POST /plot` (SymPy + matplotlib), `sandbox.py` y precarga del forkserver |
| `cd8505e` | App: `features/plot` (`PlotSpec`, `PlotRepository`, `PlotView`), bloques ` ```plot ` y botón «Gráfica» |

### Backend `/plot`
- Cuerpo: `exprs` (1–5), `var`, `x_min`/`x_max`, `y_min`/`y_max` opcionales (automáticos por percentiles 2–98 si se omiten), `theme` (`light`/`dark`), `width`/`height` en px lógicos y `scale` (1–3). Devuelve un **PNG transparente**.
- Seguridad: la misma validación que `/compute`. Cada expresión solo puede depender de la variable (`a*x` → 400 indicando qué sobra). Se ejecuta en el subproceso aislado (5 s, 1 GiB).
- Calidad: corta las asíntotas (`tan`, `1/x`), descarta valores complejos (`sqrt(x)`, `ln(x)`), muestra la leyenda en LaTeX (`\dfrac`, y texto plano si mathtext no puede) y usa una paleta distinta para tema claro y oscuro. `factorial` y otras funciones sin versión numpy se evalúan con mpmath.
- Dependencias nuevas: **matplotlib 3.11 + numpy 2.5** (unos 80 MB en el venv).

### Rendimiento del subproceso aislado (`sandbox.py`)
- Generalizado para `/compute` y `/plot`. El forkserver precarga SymPy, numpy y matplotlib, y **dibuja una gráfica de calentamiento**: la primera gráfica de cada proceso costaba unos 1,3 s y ahora unos 0,4 s.
- Se precarga también `__main__`. Antes, **cada subproceso volvía a ejecutar el script principal** (pytest o uvicorn), con un coste aproximado de 0,5–0,8 s por petición. La suite del backend bajó de 37 s a 17 s.
- `OPENBLAS_NUM_THREADS=1` para que el límite de memoria `RLIMIT_AS` no choque con los hilos de BLAS.
- El forkserver arranca en un hilo en segundo plano al iniciar el servidor (unos 3–4 s), para que la primera petición no espere.

### App
- **Bloque ` ```plot `** en las notas: una expresión por línea, con opciones `x: -2pi, 2pi`, `y: -1, 1` y `var: t`. Si el bloque no es válido, se explica en la vista previa (p. ej. «Rango de x: el mínimo debe ser menor»).
- **`PlotView`**: pide la imagen con el ancho disponible (en saltos de 50 px), el tema y la densidad de píxeles. Espera 400 ms mientras se escribe, mantiene visible la imagen anterior, muestra una barra de progreso y ofrece «Reintentar» en los errores. Guarda en caché las últimas 32 gráficas.
- Botón **«Gráfica»** en el editor: inserta un bloque de ejemplo, o uno con la expresión seleccionada.

### Verificación
| Comprobación | Resultado |
|---|---|
| `pytest` (backend) | **85 passed** (31 de `/plot`: variantes, seguridad, validación, sin valores reales, timeout) |
| `flutter analyze` | No issues found |
| `flutter test` | **50 passed** |
| Prueba de punta a punta en Linux (con gráfica real) | **3 de 3 ejecuciones seguidas pasan** |
| Revisión visual | Gráficas clara y oscura (asíntotas cortadas, semicircunferencia, leyenda LaTeX) y gráfica dentro del editor con tema oscuro |

### Incidencias
- **Prueba de punta a punta intermitente (corregida):** `find.text(título)` encontraba el título dentro del `TextField` del diálogo y no en la lista. Ahora busca `ListTile`.
- **Timeout de `/plot` con la máquina cargada:** con 2 núcleos, el navegador ocupando ~40 % de CPU y la compilación de Flutter, una gráfica superó los 5 s (408). Se añadió «Reintentar» en `PlotView`, y la prueba de punta a punta se ejecuta con `CUADERNO_COMPUTE_TIMEOUT=15`, porque verifica el flujo y no el rendimiento. El límite de 5 s del producto no cambia.
- **Al reiniciar el backend**, uvicorn esperaba indefinidamente a que se cerraran las conexiones abiertas por la pestaña de Chromium. Usar `--timeout-graceful-shutdown 3` en desarrollo.

### Pendiente en la v0.2
- Visor de PDF con extracción de texto. Antes hay que decidir las dependencias (`pypdf` en el backend; visor en Flutter, p. ej. `pdfrx`).
- Opcional: «Insertar gráfica» desde el panel de cálculo, con la expresión o su resultado.

---

## 2026-11-03/04 — Fase 2 (v0.2), parte 2: PDF, diagramas, teclado científico e interfaz

| Commit | Contenido |
|---|---|
| `fea2e94` | Backend: migraciones versionadas, `cover`/`paper`, biblioteca `/documents` (pypdf aislado) y conversión de Unicode a LaTeX |
| `d311aa2` | Backend: `/diagram` (función, cuerpo libre, tiro parabólico, grafos con NetworkX) |
| `1a4d0b0` | App: `FigureSpec`/`FigureView`, bloques ` ```diagram `, representación visual al calcular y menú de plantillas |
| `082a6e8` | App: teclado de símbolos científicos |
| `2dae314` | App: biblioteca y visor de PDF con extracción a la nota |
| `054e36c` | App: estantería con portadas ilustradas y papel de notas |
| `77b9205` | App: icono propio (Web y Linux) y prueba de punta a punta ampliada |

### Decisiones
- **Sin retratos de científicos:** las imágenes y nombres de Einstein, Curie y Sagan tienen derechos de imagen gestionados por sus herederos (sobre todo Einstein). Las portadas homenaje usan su obra: E = mc² y el espacio-tiempo curvado; el polonio y el radio; el «punto azul pálido». Si se consiguen imágenes con licencia, pueden añadirse como portadas.
- **Icono:** el primer diseño, un átomo de tres órbitas, se parecía demasiado al logo de React y se cambió por una página cuadriculada con una gráfica y un átomo de dos órbitas.
- **Fórmulas de PDF:** pypdf extrae texto, no LaTeX. La conversión de Unicode a LaTeX es aproximada y la interfaz lo dice. Convertir con fiabilidad requeriría OCR matemático, una dependencia pesada que no se ha incluido.
- **`/diagram` como endpoint propio** junto a `/plot`, en el mismo router: así cada tipo valida sus campos con un modelo Pydantic discriminado por `kind`.
- **Dependencias nuevas** (aprobadas): `pypdf`, `networkx`, `pdfrx`. Añadida además **`file_selector`**, el paquete oficial y ligero de Flutter para elegir archivos, necesario para importar PDF.

### Verificación
| Comprobación | Resultado |
|---|---|
| `pytest` (backend) | **136 passed** |
| `ruff check` / `ruff format` | OK |
| `flutter analyze` | No issues found |
| `flutter test` | **206 passed** (incluye que cada símbolo del catálogo se interpreta en flutter_math_fork, y que todas las portadas y papeles se dibujan en tema claro y oscuro) |
| Revisión visual | Los 6 tipos de diagrama y el icono (512 px, adaptable y favicon) |
| Prueba de punta a punta en Linux (diagramas, papel, PDF real) | ✅ **Pasa** al relanzarla con el navegador cerrado (el primer intento se detuvo por falta de memoria: 3,4 GB de RAM). Compila la app Linux con pdfrx (pdfium) y las capturas muestran el PDF dibujado con su texto extraído, el papel milimetrado y el diagrama de la derivada |

### Ajustes tras la revisión visual
- Los ceros numéricos de la bisección (`-4.55e-21`) se muestran como `0` en las etiquetas de los diagramas.
- La portada de Física pasa a ser un átomo de Bohr (órbitas circulares y un fotón): el átomo de tres elipses se parecía al logo de React, por la misma razón que se cambió el icono.

### Cómo ejecutar la prueba de punta a punta
En esta máquina conviene cerrar antes el navegador.
```bash
cd app && flutter test integration_test -d linux \
  --dart-define=API_BASE_URL=http://127.0.0.1:8001 \
  --dart-define=SAMPLE_PDF=/ruta/a/un.pdf
```

### Visor de PDF en Web ✅
- `integration_test/pdf_web_test.dart` y `test_driver/integration_test.dart`: abre un PDF ya importado desde la biblioteca y espera a que pdfium (WASM) lo cargue (2 páginas). Pasa a la página 2 desde el panel, inserta la cita y comprueba la nota. Guarda capturas con `binding.takeScreenshot`.
- Resultado: **pasa** en Chromium 156 sin interfaz (`flutter drive -d web-server --headless --release`). Las capturas muestran el PDF dibujado y el texto extraído (`∮`, `ε₀`, `∂`, `∇²`), y el visor sigue la página elegida en el panel.
- Requisito instalado: `chromedriver` 156 (paquete de Fedora, misma versión que Chromium).
- Lecciones:
  - En Web, `tester.enterText` solo funciona tras `binding.testTextInput.register()`, porque el texto entra por un `<input>` del navegador.
  - Los errores de los tests en Web llegan sin mensaje: la prueba guarda el paso y el error en `reportData` (`writeResponseOnFailure: true`).
- Cómo ejecutarla (con el backend en marcha y un PDF subido como `muestra-web.pdf`):
  ```bash
  chromedriver --port=4444 &
  cd app && CHROME_EXECUTABLE=/usr/bin/chromium-browser flutter drive \
    -d web-server --browser-name=chrome --headless --release \
    --driver=test_driver/integration_test.dart \
    --target=integration_test/pdf_web_test.dart \
    --dart-define=API_BASE_URL=http://127.0.0.1:8001 \
    --dart-define=PDF_NAME=muestra-web.pdf
  ```

### Versión
- Etiqueta **`v0.2.0`** (anotada) creada el 2026-11-04.
- El teclado científico aún no se muestra en el panel de cálculo, solo en el editor.

---

## 2026-11-04 — Fase 3 (v0.3): escritura a mano con lápiz y presión

Decisión del usuario: **bloques de dibujo** (` ```ink `) dentro de las notas, frente a una capa sobre la nota o a notas solo a mano.

| Commit | Contenido |
|---|---|
| `5cf070a` | Backend: migración 2 (`drawings`) y `/drawings`; versión `0.3.0-dev` |
| (este) | App: `features/ink` (lienzo, editor, vista previa) e integración con las notas |

### Qué hace
- Botón **«Dibujo»** en el editor: crea el dibujo, inserta su bloque y abre el lienzo a pantalla completa. Al volver, la vista previa lo muestra y al tocarlo se edita.
- **Presión:** el grosor varía con la presión de cada punto (0,35× a 1,65× el grosor base). El ratón dibuja con grosor fijo.
- **Lápiz y dedo:**
  - El extremo borrador del lápiz borra.
  - El dedo dibuja por defecto, pero en cuanto se detecta un lápiz deja de hacerlo, con aviso (se puede volver a activar).
  - Mientras el lápiz está apoyado, y hasta 600 ms después, el dedo nunca dibuja: así se descarta la palma.
- **Herramientas:** lápiz, resaltador (semitransparente, de un solo trazado), borrador por trazo, 6 colores (el negro se ve claro en tema oscuro), 3 grosores, deshacer y rehacer (Ctrl+Z / Ctrl+Y) y borrar todo.
- **Guardado:** automático 800 ms después de cada cambio y al salir, en JSON compacto (coordenadas redondeadas a décimas y presión a centésimas).

### Verificación
| Comprobación | Resultado |
|---|---|
| `pytest` | **149 passed** (14 de `/drawings`: CRUD, cascada, validación de trazos y límites) |
| `flutter analyze` | No issues found |
| `flutter test` | **220 passed** (14 de tinta: JSON, presión, borrador, deshacer y rehacer, lápiz, dedo, palma, extremo borrador y flujo completo) |
| Prueba de punta a punta en Linux | **Pasa**: un trazo con el ratón y otro con un lápiz simulado de presión creciente; la captura muestra el trazo engordando y el aviso de rechazo de palma |

### Lecciones
- Flutter informa `pressureMin = pressureMax = 1` cuando no hay rango. Hubo que distinguir el «sin presión» (valor 1) de un valor real entre 0 y 1.
- En las pruebas de integración, los eventos de puntero del test deben ir por `tester.sendEventToBinding`. Si se pasan a `handlePointerEvent`, se tratan como del dispositivo real y se ignoran.

### Pendiente
- Probar con un **lápiz real**: esta máquina no tiene tableta gráfica.
- Zoom y desplazamiento con dos dedos, y lienzos más altos.
- Limpiar los dibujos cuyo bloque se borró de la nota.
