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

## Fase 2 — v0.2 Visualización y exportación
- Gráficas 2D de funciones a partir de una expresión.
- Exportar nota a Markdown y PDF.
- Búsqueda de texto en notas.

## Fase 3 — v0.3 Empaquetado y Mobile
- Paquete Linux (AppImage o Flatpak) que arranque el backend solo.
- Builds Android/iOS (estudiar cálculo en el dispositivo o backend remoto opcional).

## Fase 4 — v0.4+ Sincronización (opcional)
- Sincronización opcional entre dispositivos.
- Etiquetas, enlaces entre notas e historial de versiones.
