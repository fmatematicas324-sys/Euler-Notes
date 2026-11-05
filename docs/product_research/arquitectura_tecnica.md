# Arquitectura técnica objetivo — sin conexión y lienzo científico

> Estado: **propuesta [P]. No autorizada para implementarse.**
> Marcas: [H] hecho comprobado · [W] verificado en la web o en pub.dev el 2026-11-05 · [C] conocimiento previo no verificado · [Hip] hipótesis · [P] propuesta.

## 1. Punto de partida [H]
- La app accede a todo por `ApiClient` (HTTP). Los repositorios (`NotebooksRepository`, `NotesRepository`, etc.) son clases concretas que llaman al backend.
- `shared_preferences` solo guarda la URL del servidor.
- Backend: SQLite con `PRAGMA user_version` y migraciones que solo se añaden; tablas `notebooks`, `notes`, `documents` y `drawings`; los PDF como archivos en `data/documents/`.
- Tinta: `Stroke` con puntos `[x, y, presión]` en unidades del lienzo, guardados como JSON en `drawings`. `InkCanvas` usa `Listener` + `CustomPainter` y guarda en caché un `Picture` con los trazos terminados.

## 2. Almacenamiento local: comparación

Versiones consultadas en pub.dev el 2026-11-05 **[W]**:

| Opción | Versión / última publicación | Tipo | Android | Linux | Web | Migraciones | Mantenimiento |
|---|---|---|---|---|---|---|---|
| **Drift** (+ `drift_flutter`) | 2.35.3 / 2026-10-23 | SQL tipado sobre `sqlite3` (FFI), con generación de código | ✅ | ✅ | ✅ (WASM) [C] | Versionadas, con pasos generados y utilidades para probarlas [C] | Activo [W] |
| **sqflite** | 2.4.5 / 2026-10-21 | SQL directo por canal de plataforma | ✅ | Solo con `sqflite_common_ffi` 2.4.5 | ❌ (hay paquetes aparte) [C] | Manuales (`onUpgrade`) | Activo [W] |
| **sqlite3** (directo) | 3.9.0 / 2026-11-05 | SQL directo por FFI | ✅ | ✅ | ✅ (WASM) [C] | Manuales (como el backend actual) | Activo [W]; `sqlite3_flutter_libs` aparece "eol: actualizar a sqlite3 3.x" [W] |
| ObjectBox | 5.3.2 / 2026-05-20 | NoSQL de objetos | ✅ | ✅ | ❌ [C] | Automáticas por anotaciones [C] | Activo [W]; núcleo nativo de código cerrado [C] |
| Isar | 3.1.0 / 2023-04-25 | NoSQL | — | — | — | — | **Abandonado** [W]; existe la versión comunitaria `isar_community` 3.4.1 [W] |
| Hive CE | 2.22.0 / 2026-10-14 | Clave-valor | ✅ | ✅ | ✅ | No relacional | Activo [W] |
| Sembast | 3.10.0 / 2026-11-03 | NoSQL (archivo JSON) | ✅ | ✅ | ✅ | Manual | Activo [W]; carga la base entera en memoria [C] |
| Realm | 20.2.0 / 2025-09-24 | NoSQL de objetos | — | — | — | — | MongoDB anunció en 2024 que dejaba de desarrollar estos SDK [C] — **descartado** |
| PowerSync | 2.6.0 / 2026-11-02 | Capa de sincronización sobre SQLite | ✅ | ✅ | ✅ [C] | — | Activo [W]. **Candidato para sincronizar más adelante, no para el MVP** |

### Valoración [Hip/P]
| Criterio | Drift | sqflite | sqlite3 directo |
|---|---|---|---|
| Seguridad de tipos | ★★★ | ★ | ★ |
| Migraciones comprobables | ★★★ | ★ | ★★ (el patrón del backend ya existe) |
| Consultas reactivas para Riverpod | ★★★ (streams) | ★ | ★ |
| Rendimiento con BLOB de tinta | ★★★ (FFI, sin canal) | ★★ (pasa por el canal de plataforma) [Hip] | ★★★ |
| Búsqueda de texto (FTS5) | ✅ [C] | Depende del SQLite del sistema [C] | ✅ [C] |
| Coste | Generación de código (`build_runner`) | Bajo | Más código manual |
| Linux + Android con el mismo código | ✅ | Requiere dos backends | ✅ |

**Recomendación [P] (ADR 10): Drift.**
- Tipos, migraciones probadas y streams encajan con Riverpod.
- Usa FFI, así que es rápido con los datos binarios de la tinta.
- Funciona igual en Android, Linux y Web.
- **Plan B:** `sqlite3` directo, reutilizando el SQL del backend, si la generación de código o las *build hooks* dan problemas en el prototipo.

**Descartadas:**
- Isar y Realm, por mantenimiento.
- Hive CE y Sembast, porque no son relacionales y Sembast mantiene todo en memoria.
- ObjectBox, por el núcleo cerrado y porque no permite SQL ni FTS5.

## 3. Arquitectura objetivo sin conexión [P]

```
UI (features/*/presentation)  ──  Riverpod
        │
Repositorios (interfaces en features/*/domain)
        │                         │
Local (Drift/SQLite)       Motor de cálculo (ComputeEngine)
  fuente principal            ├─ Remoto: FastAPI opcional (actual)
  + archivos (PDF, imágenes)  ├─ Local Dart: gráficas numéricas simples
                              └─ Local Python: según el estudio §4
```

### 3.1 Esquema local (borrador)
| Tabla | Campos clave | Notas |
|---|---|---|
| `notebooks` | id (UUID v7), title, cover, created_at, updated_at, deleted_at | Portada (ya existe en el cliente) |
| `sections` | id, notebook_id, title, position | Nueva |
| `pages` | id, section_id/notebook_id, position, size (`a4`, `letter`, `infinite`), orientation, paper | Sustituye a la "nota" como unidad |
| `page_items` | id, page_id, kind (`text`, `formula`, `image`, `figure`, `pdf_clip`), x, y, w, h, z, payload (JSON) | `text` contiene el Markdown actual |
| `strokes` | id, page_id (o `pdf_page_id`), tool, color, width, bbox (4 reales), points BLOB | Puntos empaquetados `Float32 [x, y, presión, t]` |
| `documents` | id, title, file_path, sha256, pages, created_at | El archivo se copia a la carpeta de la app |
| `pdf_annotations` | id, document_id, page_index → enlace a `strokes` | Anotar sin modificar el PDF |
| `pages_fts` | FTS5 sobre títulos, texto y texto de PDF | Búsqueda |

- **Notas existentes [P]:** cada nota pasa a ser una página "infinita" con un `page_item` de texto que contiene el Markdown completo. Los bloques ` ```ink ` se mantienen y se muestran como hoy. **No se elimina ninguna función.**
- **[Hip] Tamaño de la tinta:** con `Float32 ×4`, cada punto ocupa 16 B frente a ~25–35 B en JSON. Una página densa (~30.000 puntos) ocuparía ~0,5 MB.

### 3.2 Guardado automático fiable [P]
1. **Tinta:** cada trazo terminado se guarda de inmediato en una transacción. Es una inserción pequeña y no hace falta esperar.
2. **Texto:** se guarda tras 800 ms sin cambios (como hoy), y además **siempre** al pasar a `AppLifecycleState.paused/inactive`, al salir de la pantalla y al cambiar de página.
3. SQLite en modo **WAL** con `synchronous=NORMAL`. **[Hip]** Basta para resistir que el sistema cierre la app.
4. **Borrador de recuperación:** el texto sin guardar se escribe en una tabla `drafts` antes de la transacción principal.
5. **Pruebas:** "matar" la app (`adb shell am kill`) en mitad de una escritura y comprobar que no se pierde nada.

### 3.3 Archivos
- PDF e imágenes en `getApplicationSupportDirectory()/documents/<sha256>.pdf` (requiere `path_provider` [C]). La base de datos solo guarda la ruta relativa.
- Copia de seguridad: exportar un `.eulernotes` (ZIP con `db.sqlite` + archivos). **[P]** Es una base sencilla antes de sincronizar.

### 3.4 Migración desde el backend actual [P]
- Importación única desde la app: "Importar desde servidor". Lee `/notebooks`, `/notes`, `/drawings` y `/documents` y lo escribe localmente.
- El backend no cambia y la importación se puede repetir sin duplicar (identificadores de origen guardados).

## 4. Motor de cálculo: estudio comparativo (ADR 13)

| Opción | Sin conexión | Tamaño APK [Hip] | SymPy completo | Gráficas | Aislamiento y tiempo máximo | Linux | Licencia | Complejidad |
|---|---|---|---|---|---|---|---|---|
| **A. FastAPI remoto opcional** (actual) | ❌ | 0 | ✅ | ✅ matplotlib | ✅ (forkserver + rlimit) | ✅ | Propia | Baja (ya existe) |
| **B. `serious_python`** 6.1.3 [W] | ✅ | +40–80 MB | ✅ (SymPy es Python puro) [C] | ◐ matplotlib/numpy necesitan versiones compiladas para Android [Hip] | ◐ Python dentro del mismo proceso. **No hay `fork` seguro en Android** [Hip]. Un cálculo que no termina no se puede matar sin reiniciar el intérprete | ✅ (Linux soportado [W]) | Apache-2.0 [C] | Media-alta |
| **C. Chaquopy** | ✅ | +40–80 MB | ✅ | ✅ numpy y matplotlib en su repositorio [W, 2022] | ◐ Se puede lanzar en un **proceso Android separado** (`android:process`) y matarlo al pasarse de tiempo [Hip] | ❌ solo Android (Linux seguiría con el backend) | MIT desde la 12.0.1 (2022) [W] | Alta (canal de plataforma Kotlin ↔ Dart) |
| **D. CAS en Dart** (`math_expressions` u otros) | ✅ | ~0 | ❌ solo evaluación y derivadas básicas [C] | ✅ con `CustomPainter` | ✅ (Isolate) | ✅ | Abiertas | Baja para lo numérico |
| **E. Giac/Xcas por FFI** (C++) | ✅ | +10–20 MB [Hip] | ✅ (otro CAS, no SymPy) | ◐ | ◐ | ✅ | **GPL** [C]: obligaría a publicar Euler Notes como GPL | Alta |
| **F. CAS en JavaScript en WebView** (p. ej. Compute Engine, Nerdamer) | ✅ | +5 MB [Hip] | ◐ | ◐ | ◐ | ◐ | MIT [C] | Media |

### Recomendación [P]
1. **MVP:** opción **A + D**.
   - Las gráficas numéricas y la evaluación básica funcionan en Dart sin conexión.
   - SymPy se usa a través del servidor opcional, con el mensaje "motor no disponible" si falta.
   - Ninguna función actual se pierde.
2. **Estudio antes de la v0.7:** un prototipo de **B** y otro de **C**, con el mismo banco de pruebas:
   - Tamaño del APK por arquitectura (arm64-v8a).
   - Arranque en frío del intérprete.
   - Memoria en reposo y con `integrate(sin(x)**10)`.
   - Posibilidad de cortar un cálculo que no termina.
   - Esfuerzo de mantener la versión de Linux.
   - **Criterio de éxito:** < +60 MB, arranque < 3 s, y cancelación fiable sin cerrar la app.
3. **Descartar E** por la licencia GPL, salvo que el proyecto decida ser GPL.

**[H]** El aislamiento actual (`forkserver` + `RLIMIT_AS`) **no** se puede llevar a Android. Cualquier opción local necesita otro diseño de aislamiento.

## 5. Lienzo científico basado en páginas

### 5.1 Modelo
- **Unidad:** punto tipográfico (1/72"). A4 = 595 × 842 pt y Carta = 612 × 792 pt (medidas estándar). La página "infinita" crece hacia abajo.
- **Capas por página** (de abajo arriba):
  1. Papel (cuadrícula, milimetrado, etc.).
  2. PDF rasterizado (si es una página de documento).
  3. Objetos: texto, fórmula, imagen y figura.
  4. Tinta.
  5. Selección y herramientas.
- Todo se guarda en **coordenadas de página**, de modo que el zoom no altera los datos.

### 5.2 Zoom y desplazamiento [P]
- Lista vertical virtualizada de páginas (`ListView.builder` o un `CustomScrollView` propio) bajo una transformación de zoom de 0,5× a 8×.
- **Gestos:** el **lápiz** dibuja, **dos dedos** hacen zoom y desplazan, y **un dedo** desplaza (configurable). Se reutiliza la lógica actual de distinguir lápiz y dedo y de rechazar la palma.
- **[Hip]** `InteractiveViewer` sirve para un prototipo, pero entra en conflicto con el `Listener` de la tinta en los gestos. Probablemente haga falta un detector de gestos propio.
- **Renderizado por mosaicos:**
  - Al hacer zoom, la página se dibuja con el `Picture` vectorial (nítido).
  - En reposo se guarda una imagen en caché por página y nivel de zoom.
  - Solo se dibujan las páginas visibles ±1.

### 5.3 Tinta vectorial [P]
- Se reutiliza el modelo `Stroke`, `InkPoint` y `widthForPressure` [H], añadiendo el tiempo `t` y el `bbox`.
- **Trazo suavizado:** opción de calcular el contorno con `perfect_freehand` 2.5.2+1 [W] (MIT [C]) o seguir con la técnica actual. Se decidirá por calidad y CPU.
- **Borrador parcial:** divide el trazo en los puntos que toca el borrador.
- **Lazo:** prueba de punto en polígono sobre el `bbox` y después sobre los puntos; permite mover, escalar, cambiar color y copiar.
- **Índice espacial:** cuadrícula por página (celdas de 64 pt) para que borrar y seleccionar sean O(trazos cercanos).
- **[Hip] Latencia:** Android ofrece renderizado de baja latencia (*front-buffered*) y predicción de movimiento en AndroidX, pero Flutter no los expone. Primero hay que **medir** la latencia en una tablet real; solo si es mala se estudiaría una vista nativa.

### 5.4 Texto y fórmulas
- Objeto `text`: Markdown + LaTeX, editado en un cuadro o en una hoja inferior y mostrado con el `markdown_preview` actual [H].
- Objeto `formula`: LaTeX mostrado con `MathFormula` (`flutter_math_fork`) [H]. Botones para "calcular" (el motor de §4) e "insertar gráfica".
- Teclado de símbolos [H], adaptado a una barra táctil.

### 5.5 Imágenes
- Importar con `file_selector` [H] o la cámara (paquete por definir), guardar en la carpeta de archivos y crear un objeto `image` con recorte.

### 5.6 Anotar sobre PDF
- `pdfrx` [H] ya muestra las páginas y extrae su texto. Sobre cada página va una capa de tinta en **coordenadas de la página PDF**, guardada en `strokes` + `pdf_annotations`. **El archivo original no se modifica.**
- Resaltar texto usando las posiciones de texto de pdfrx **[Hip]: comprobar qué expone su API**.
- Exportar con anotaciones: aplanar en un PDF nuevo (paquete por estudiar, p. ej. `pdf` [C]).
- **Pantalla dividida** PDF + página del cuaderno en tablets en horizontal, con "recorte enlazado" (objeto `pdf_clip` que guarda documento, página y rectángulo).

### 5.7 Componentes reutilizables
| Componente actual [H] | Reutilización en el lienzo |
|---|---|
| `features/ink/domain/stroke.dart` (`Stroke`, `widthForPressure`, colores) | Directa, añadiendo campos |
| `features/ink/presentation/ink_canvas.dart` (lápiz/dedo, palma, caché `Picture`) | Lógica base de la capa de tinta; separarla del tamaño fijo |
| `ink_editor_screen.dart` (herramientas, deshacer/rehacer) | Barra de herramientas y pila de deshacer |
| `notes/presentation/paper_background.dart` + `paper_style.dart` | Capa de papel (añadir A4/Carta, polar y logarítmico) |
| `notes/presentation/markdown_preview.dart` | Objeto de texto |
| `core/widgets/math_formula.dart` | Objeto de fórmula |
| `plot/` (`PlotSpec`, `DiagramSpec`, `FigureView`) | Objeto de figura; la gráfica en Dart reutiliza `PlotSpec` |
| `symbols/` (catálogo LaTeX e inserción) | Barra de símbolos táctil |
| `documents/presentation/document_viewer_screen.dart` (pdfrx) | Base del visor con capa de anotación |
| `compute/` (`ComputeRepository`, `compute_panel`) | Se mantiene detrás de la interfaz `ComputeEngine` |
| `notebooks/` (portadas, estantería) | Sin cambios; cambia solo el repositorio |
| `backend/app/storage/schema.sql` + migraciones | Base del esquema local |

## 6. Compatibilidad Android / Linux [Hip salvo indicación]
- **Android:**
  - Probar desde Android 8 o 9 (las apps de la competencia piden ~3 GB de RAM [W]).
  - Al compilar por arquitectura (`--split-per-abi`), el APK baja de 78 MB [H] a ~25–30 MB por ABI.
  - El ciclo de vida obliga a guardar al pausar (§3.2).
- **Linux:** Drift y sqlite3 vía FFI funcionan. El lápiz en Linux depende de X11 o Wayland y del driver de la tableta; la presión puede no llegar.
- **Web:** Drift WASM necesita cabeceras COOP/COEP para la persistencia más rápida [C]. Hasta decidirlo, la Web puede seguir usando el backend.

## 7. Prototipos propuestos (cada uno de 1–3 días, desechables, en ramas `spike/*`)
1. `spike/drift`: Drift + sqlite3 3.x en Android, Linux y Web; 10.000 trazos; tiempos de lectura y escritura.
2. `spike/canvas`: 20 páginas A4 con zoom, lápiz, dedo y palma, y latencia medida en una tablet real.
3. `spike/python-android`: B frente a C con el banco de pruebas de §4.
4. `spike/pdf-ink`: capa de tinta sobre pdfrx con zoom sincronizado.
