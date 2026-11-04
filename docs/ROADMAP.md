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

## Fase 2 — v0.2 Gráficas 2D y visor de PDF
Objetivo: visualizar funciones y consultar material en PDF dentro del cuaderno. A partir de esta versión, las fases se orientan a **tablet Android**.

### Gráficas
- [x] Backend: `POST /plot` (SymPy + matplotlib) que devuelve un PNG. Admite hasta 5 expresiones, rango de la variable, rango de `y` opcional (automático si se omite), tema claro u oscuro, tamaño y escala de píxeles. Se ejecuta en el mismo subproceso aislado (con límites de tiempo y memoria) que `/compute`.
- [x] Flutter: widget `PlotView` (carga con espera, caché, error, tema y densidad de píxeles del dispositivo).
- [x] Notas: bloques ` ```plot ` en Markdown que se muestran como gráficas en la vista previa, y botón «Gráfica» en el editor.

### Visor de PDF
- [ ] Backend: subida de PDF asociada a una nota y `POST /pdf/extract` (texto por página).
- [ ] Flutter: visor de PDF con navegación por páginas, y opción de copiar o insertar en la nota el texto extraído.
- [ ] Dependencias a decidir antes de empezar (consultar): extractor en Python (`pypdf`) y visor en Flutter (`pdfrx`), o renderizar las páginas en el backend.

**Salida:** gráficas en las notas, y un PDF abierto y con su texto extraído en Web y Linux. Se etiqueta `v0.2.0`.

## Fase 3 — v0.3 Escritura a mano (lápiz/stylus)
- [ ] Lienzo de escritura con `CustomPainter` y `Listener`: trazos suavizados y grosor según la **presión** (`PointerEvent.pressure`).
- [ ] Distinguir el lápiz (`PointerDeviceKind.stylus`) del dedo: el dedo hace scroll o zoom y el lápiz dibuja. Esto sirve también para ignorar la palma de la mano.
- [ ] Herramientas básicas: lápiz, borrador por trazo, deshacer y rehacer, colores y grosores.
- [ ] Persistencia de los trazos: modelo `Stroke` (puntos, presión, color, grosor) guardado como bloque de la nota, y endpoint en el backend.
- [ ] Rendimiento: capas de trazos terminados guardadas en caché (`Picture`) para mantener 60 fps con cientos de trazos.

**Salida:** tomar notas a mano en un cuaderno, con presión, en una tablet con lápiz. Se etiqueta `v0.3.0`.

## Fase 4 — v0.4 Teclado científico y APK para tablet Android
- [ ] Teclado de símbolos científicos (letras griegas, operadores, cálculo, conjuntos, flechas) que inserta LaTeX en el cursor del editor y expresiones en el panel de cálculo.
- [ ] Plataforma Android: `flutter create --platforms android`, interfaz adaptada a tablet (horizontal y vertical) y pruebas en un emulador de tablet.
- [ ] Toolchain Android: Android SDK y licencias (**dependencia pesada, consultar antes de instalar**).
- [ ] `flutter build apk --release`: firma, icono, nombre y versión.

**Salida:** APK instalable en una tablet Android con las funciones de v0.1–v0.4. Se etiqueta `v0.4.0`.

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
