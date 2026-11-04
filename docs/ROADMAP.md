# Cuaderno Científico — Roadmap

> Versión del documento: v0.1 · Estado: borrador aprobado (Fase 0)

## Fase 0 — Cimientos
- [x] Reglas del proyecto (`CLAUDE.md`).
- [x] Documentación: `PRODUCT_SPEC.md`, `ARCHITECTURE.md`, `ROADMAP.md`.
- [x] Esqueleto de carpetas `app/` y `backend/`, `.gitignore` y `README.md` raíz.
- [x] Instalar Flutter SDK estable (Web + Linux) y comprobar con `flutter doctor`.
- [x] Crear el entorno virtual `backend/.venv` e instalar las dependencias mínimas.

**Salida:** `flutter doctor` OK para Web/Linux; el entorno Python está listo.

## Fase 1 — v0.1 MVP
### Backend
- [x] `main.py` con `/health`, CORS solo para localhost y manejo de errores unificado.
- [x] Repositorio SQLite + `schema.sql`.
- [x] CRUD de `/notebooks` y `/notes` con sus tests.
- [x] Motor de cálculo SymPy seguro (lista blanca + tiempo máximo) y `POST /compute` con sus tests, incluidos casos maliciosos.

### App
- [x] `flutter create` con plataformas web y linux; estructura `core/` + `features/`.
- [x] `api_client` y configuración de la URL del backend.
- [x] Pantalla de cuadernos (listar, crear, renombrar, eliminar).
- [x] Pantalla de notas de un cuaderno.
- [x] Editor dividido Markdown + vista previa con LaTeX.
- [x] Panel de cálculo con opción de insertar el resultado en la nota.

**Salida:** se cumplen los criterios de aceptación de `PRODUCT_SPEC.md §5`. Se etiqueta `v0.1.0`.

## Fase 2 — v0.2 Gráficas, diagramas, PDF y edición científica
Objetivo: visualizar y consultar material científico dentro del cuaderno, con una interfaz cuidada. A partir de esta versión, las fases se orientan a **tablet Android**.

### Gráficas y diagramas
- [x] Backend: `POST /plot` (SymPy + matplotlib), PNG transparente en tema claro u oscuro, ejecutado en el subproceso aislado.
- [x] Backend: `POST /diagram`: `function` (análisis visual de simplificar, derivar, integrar o resolver), `forces` (cuerpo libre), `projectile` (tiro parabólico) y `graph` (NetworkX).
- [x] Flutter: `FigureView` común (espera al escribir, caché, tema, densidad de píxeles, reintentar).
- [x] Notas: bloques ` ```plot ` y ` ```diagram ` y menú «Gráfica» con plantillas.
- [x] Panel de cálculo: «Añadir representación visual», que inserta el diagrama de la operación junto al resultado.

### Visor de PDF
- [x] Backend: biblioteca `/documents` (subir, listar, descargar, texto por página, borrar), con pypdf en el subproceso aislado.
- [x] Flutter: visor pdfrx con el texto de la página para insertarlo como cita con la fuente, o como fórmula (conversión aproximada de Unicode a LaTeX).
- [x] Visor verificado con pdfium en la app Linux (prueba de punta a punta).
- [ ] Verificar el visor en Web (pdfium WASM).

### Edición científica
- [x] Teclado de símbolos científicos (adelantado desde la v0.4): cálculo, vectores, matrices, griegas, relaciones y física.

### Interfaz
- [x] Estantería de cuadernos en cuadrícula con 8 portadas ilustradas (incluidos homenajes a Einstein, Curie y Sagan basados en su obra, sin retratos).
- [x] Papel por nota: blanco, renglonado, milimetrado, punteado y semilogarítmico.
- [x] Icono propio para Web (favicon y PWA) y para la ventana de Linux.

**Salida:** se etiqueta `v0.2.0` cuando se compruebe el visor de PDF en Web (en Linux ya pasa la prueba de punta a punta).

## Fase 3 — v0.3 Escritura a mano (lápiz/stylus)
- [ ] Lienzo de escritura con `CustomPainter` y `Listener`: trazos suavizados y grosor según la **presión** (`PointerEvent.pressure`).
- [ ] Distinguir el lápiz (`PointerDeviceKind.stylus`) del dedo: el dedo hace scroll o zoom y el lápiz dibuja. Esto sirve también para ignorar la palma de la mano.
- [ ] Herramientas básicas: lápiz, borrador por trazo, deshacer y rehacer, colores y grosores.
- [ ] Persistencia de los trazos: modelo `Stroke` (puntos, presión, color, grosor) guardado como bloque de la nota, y endpoint en el backend.
- [ ] Rendimiento: capas de trazos terminados guardadas en caché (`Picture`) para mantener 60 fps con cientos de trazos.

**Salida:** tomar notas a mano en un cuaderno, con presión, en una tablet con lápiz. Se etiqueta `v0.3.0`.

## Fase 4 — v0.4 APK para tablet Android
- [x] ~~Teclado de símbolos científicos~~: adelantado a la v0.2. Pendiente aquí: adaptarlo a pantalla táctil y como teclado del panel de cálculo.
- [ ] Plataforma Android: `flutter create --platforms android`, interfaz adaptada a tablet (horizontal y vertical) y pruebas en un emulador de tablet.
- [ ] Toolchain Android: Android SDK y licencias (**dependencia pesada, consultar antes de instalar**).
- [ ] `flutter build apk --release`: firma, icono, nombre y versión.

**Salida:** APK instalable en una tablet Android con las funciones de v0.1–v0.4. El icono adaptable se genera con `tool/generate_app_icons_test.dart`. Se etiqueta `v0.4.0`.

### ⚠️ Decisión de arquitectura pendiente (antes de la v0.4)
El backend Python (FastAPI + SymPy + matplotlib) corre hoy en el mismo equipo que la app; en Android eso no funciona tal cual. Opciones:
1. **Backend remoto o en la red local:** la tablet se conecta a un PC o servidor. Es lo más simple, pero necesita red y requiere autenticación y TLS.
2. **Python embebido en el APK** (p. ej. Chaquopy o `serious_python`): funciona sin conexión, pero el APK pesa más (unos 50–100 MB) y la compilación se complica.
3. **Pasar el cálculo a Dart:** funciona sin conexión y el APK es ligero, pero no hay un equivalente maduro de SymPy.

La decisión irá en un ADR en ARCHITECTURE §9.

## Más adelante (v0.5+)
- Exportar notas a Markdown y PDF.
- Búsqueda de texto en notas y PDFs.
- Sincronización opcional entre dispositivos, etiquetas y enlaces entre notas.
