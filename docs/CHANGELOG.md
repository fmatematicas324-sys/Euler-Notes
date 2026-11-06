# Changelog — Euler Notes

Formato basado en *Keep a Changelog*. Versionado semántico. Reconstruido a partir del historial de Git y del `DEVELOPMENT_LOG.md`.

## [Sin publicar]
### Cambiado
- CI separado de las releases: `ci.yml` (Ruff, pytest, Flutter y APK de comprobación con 7 días de retención) y `release.yml` (solo tags `vX.Y.Z`, como borrador).
- Versión del backend sincronizada con la del producto (`0.4.0`), leída de `pyproject.toml`.
- Variables de entorno con prefijo `EULER_` (se siguen aceptando las `CUADERNO_`).
### Seguridad
- Misión 004 (M1): lista explícita de redes permitidas (loopback, RFC 1918, link-local, ULA) en lugar de `is_private`, que aceptaba Teredo y 6to4. Se rechazan siempre multicast, broadcast y direcciones no especificadas, y también las peticiones con cabeceras de proxy.
- Misión 004 (M2): cancelación real de peticiones HTTP (`AbortableRequest`) al agotarse el tiempo o cancelar. Códigos `timeout`, `cancelled` y `network_error`; las operaciones que crean algo avisan de que pudieron completarse.
- Misión 004 (M3): el archivo con la URL y el token queda fuera de las copias de seguridad de Android (nube y transferencia entre dispositivos).
- **Token de acceso obligatorio** (`Authorization: Bearer`) en todas las rutas salvo `/health` y la documentación, también desde el propio equipo. Se genera en `backend/data/api_token` (0600) o se fija con `EULER_API_TOKEN`; la consola indica dónde está sin mostrarlo.
- Filtro de origen: solo loopback y redes privadas (403), configurable con `EULER_ALLOWED_NETWORKS`. Defensa adicional, no sustituye al token.
- Máximo 2 tareas aisladas simultáneas (`EULER_MAX_PARALLEL_TASKS`); si no hay hueco, 503 `server_busy`.
- App: campo «Token de acceso» (oculto) en el diálogo del servidor; «Probar conexión» valida el token con `/auth/check`.
### Añadido
- Misión 017 (Etapa 2): copias de seguridad exportables. Configuración → Datos → Copia de seguridad → «Exportar copia» guarda cuadernos, notas y dibujos en un archivo `.eulernotes` verificado con SHA-256 donde elija el usuario (formato en `docs/BACKUP_FORMAT.md`, ADR 24). No modifica la base ni incluye el token. Nunca sobrescribe una copia anterior: en Android pide otro nombre si el archivo elegido ya existe; en escritorio la sustituye de forma atómica solo tras verificar la nueva. Muestra el SHA-256 completo con un botón para copiarlo.
- Misión 016 (Etapa 2, beta): modo sin conexión. Cuadernos, notas y dibujos se abren y guardan en la tablet sin la compu (Laboratorio → «Modo sin conexión»).
- Misión 015 (Etapa 2): copia local de cuadernos, notas y dibujos con importación verificada desde el servidor (Laboratorio → «Importar desde el servidor»).
- Misión 014 (Etapa 2, prototipo): base de datos local con Drift y pantalla «Laboratorio» que mide su rendimiento en el dispositivo. No cambia dónde se guardan las notas.
- Misión 013: borrador local de cada nota, reintento automático del guardado y diálogo para recuperar cambios que no llegaron al servidor.
- Misión 012: diagramas `contour` (curvas de nivel), `vector_field` (flechas o líneas de campo, con divergencia y rotacional) y `curve3d` (curvas paramétricas), con sus bloques ` ```diagram ` y plantillas.
- Misión 011: `python -m app.pair` (dirección y token con QR, `--rotar`), `tool/install_service.sh` (servicio de systemd) y `docs/CONEXION.md`. Nueva dependencia ligera: `segno`.
- Misión 010: firma estable del APK con los secretos `ANDROID_*` en `ci.yml` y `release.yml` (pendiente de que el dueño cree la clave).
- Misión 009: `AUDIT_REPORT.md` y `ONENOTE_ANALYSIS.md` en `docs/product_research/`.
- Misión 008: superficies 3D z = f(x, y) como diagrama `surface` (`POST /diagram`) y bloque ` ```diagram ` con `tipo: superficie`, con curvas de nivel opcionales en la base.
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
