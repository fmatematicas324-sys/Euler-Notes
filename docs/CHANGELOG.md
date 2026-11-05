# Changelog — Euler Notes

Formato basado en *Keep a Changelog*. Versionado semántico. Reconstruido a partir del historial de Git y del `DEVELOPMENT_LOG.md`.

## [Sin publicar]
### Cambiado
- CI separado de las releases: `ci.yml` (Ruff, pytest, Flutter y APK de comprobación con 7 días de retención) y `release.yml` (solo tags `vX.Y.Z`, como borrador).
- Versión del backend sincronizada con la del producto (`0.4.0`), leída de `pyproject.toml`.
- Variables de entorno con prefijo `EULER_` (se siguen aceptando las `CUADERNO_`).
### Seguridad
- **Token de acceso obligatorio** (`Authorization: Bearer`) en todas las rutas salvo `/health` y la documentación, también desde el propio equipo. Se genera en `backend/data/api_token` (0600) o se fija con `EULER_API_TOKEN`; la consola indica dónde está sin mostrarlo.
- Filtro de origen: solo loopback y redes privadas (403), configurable con `EULER_ALLOWED_NETWORKS`. Defensa adicional, no sustituye al token.
- Máximo 2 tareas aisladas simultáneas (`EULER_MAX_PARALLEL_TASKS`); si no hay hueco, 503 `server_busy`.
- App: campo «Token de acceso» (oculto) en el diálogo del servidor; «Probar conexión» valida el token con `/auth/check`.
### Añadido
- Ruta `GET /auth/check`.
- `docs/SERVER_SECURITY.md`: procedimientos, riesgos y estudio de `flutter_secure_storage`.
- Tiempos de espera HTTP centralizados en `ApiClient` (`ApiTimeouts`): 3 s `/health`, 10 s CRUD, 15 s `/compute`, 30 s gráficas, 60 s descarga y 120 s subida de PDF. Al agotarse: `ApiException(code: 'timeout')`.
- `tool/check_versions.py`: comprueba que `pubspec.yaml`, `pyproject.toml` y el tag coinciden.
- `docs/SIGNING.md`: estado de la firma y procedimiento de respaldo.
### Documentación
- Misión 001: auditoría técnica.
- Misión 002: investigación de competencia (`docs/product_research/`), arquitectura offline objetivo, lienzo científico, plan de la Etapa 0, `PROJECT_STATUS`, `TASKS`, `DECISIONS` y este `CHANGELOG`.

## [0.4.0] — 2026-11-05 (pre-release, solo APK)
### Añadido
- Compilación del APK de Android en GitHub Actions (`.github/workflows/android-apk.yml`) y publicación como release.
- ADR 9: en Android, el backend corre en un PC de la red local.
### Cambiado
- Versión de la app `1.0.0+1` → `0.4.0+4`.
### Eliminado
- Archivo temporal de Kotlin que estaba versionado (`android/.kotlin/sessions`).

## [0.3.0] — sin tag remoto
### Añadido
- Escritura a mano en bloques ` ```ink `: presión, rechazo de la palma, lápiz, resaltador, borrador por trazo, deshacer y rehacer.
- Backend: tabla `drawings` (migración 2) y rutas `/drawings`.
- Configuración del servidor desde la app y plataforma Android.

## [0.2.0] — sin tag remoto
### Añadido
- Gráficas 2D (`/plot`, matplotlib) y diagramas (`/diagram`).
- Biblioteca y visor de PDF (pdfrx) con texto extraído por página (pypdf, en el subproceso aislado).
- Teclado de símbolos científicos, estantería con 8 portadas, tipos de papel e icono propio.

## [0.1.0] — sin tag remoto
### Añadido
- Backend FastAPI + SQLite con CRUD de cuadernos y notas.
- Motor SymPy seguro (lista blanca, tiempo máximo y memoria limitada).
- App Flutter (Web/Linux): cuadernos, notas, editor Markdown + LaTeX y panel de cálculo.
