# Euler Notes — Registro de decisiones (ADR)

Cada decisión indica su **estado**: Aceptada · Propuesta (pendiente de aprobación) · Sustituida · Rechazada.
Las ADR 1–9 resumen `ARCHITECTURE.md §9`; desde ahora este archivo es la fuente principal.

| # | Decisión | Estado | Motivo |
|---|---|---|---|
| 1 | Backend Python en lugar de solo Dart | Aceptada → **Sustituida parcialmente por ADR 11 si se aprueba** | SymPy no tiene equivalente maduro en Dart. |
| 2 | SQLite con `sqlite3` de la stdlib, sin ORM (backend) | Aceptada | Modelo pequeño; un ORM no compensa. |
| 3 | REST/JSON entre app y backend | Aceptada (para el cálculo) | Funciona igual en Web y Linux y se depura con `/docs`. |
| 4 | Riverpod para el estado | Aceptada | Estándar, testeable y sin generación de código. |
| 5 | Gráficas renderizadas en el backend (matplotlib → PNG) | Aceptada, en revisión | Reutiliza SymPy y la calidad de matplotlib. Sin backend no hay gráficas (ver ADR 13). |
| 6 | Los PDF se analizan en el subproceso aislado | Aceptada | Son archivos no confiables. |
| 7 | Portadas, papel e icono dibujados con `CustomPainter` | Aceptada | No hay recursos de terceros y se escalan sin pérdida. |
| 8 | Tinta como bloques ` ```ink ` dentro del Markdown | Aceptada → **Sustituida por ADR 14 si se aprueba** | Evitaba que una capa se descolocara al refluir el texto. |
| 9 | En Android, el backend corre en un PC de la red local | Aceptada (provisional, v0.4) | Era la forma más rápida de tener un APK. |

---

## ADR 10 — Almacenamiento local: Drift sobre `package:sqlite3` · **Propuesta**
- **Contexto [H]:** el objetivo aprobado es que la app funcione sin conexión y que SQLite local sea la fuente principal de datos.
- **Propuesta [P]:** usar Drift 2.x como capa de persistencia de la app. Es SQL tipado, admite consultas reactivas (streams) y permite migraciones versionadas y comprobables.
- **Alternativas:** `sqflite` (+ `sqflite_common_ffi` en Linux), `sqlite3` directo, ObjectBox, Isar (comunidad), Sembast y Hive CE. La comparación está en `product_research/arquitectura_tecnica.md §2`.
- **Riesgos:** necesita `build_runner` (generación de código). **[Hip]** Hay que validar que funciona con las *build hooks* nativas de `sqlite3` 3.x en Flutter 3.47, con un prototipo previo.

## ADR 11 — El backend FastAPI pasa a ser opcional · **Propuesta**
- **[P]** La app guarda y lee todo localmente. El backend solo se usa como **motor de cálculo remoto** (SymPy y matplotlib) cuando está disponible. Sin él, las funciones de cálculo muestran "motor no disponible" y nunca bloquean la escritura.
- **Consecuencia:** el CRUD del backend queda para Web y Linux mientras se migran los datos, y después se retira o se mantiene como servidor de sincronización.

## ADR 12 — Identificadores UUID y metadatos de sincronización · **Propuesta**
- **[P]** Las tablas nuevas usan identificadores UUID v7 (texto) en lugar de `AUTOINCREMENT`, más las columnas `created_at`, `updated_at` y `deleted_at` (marcas de borrado).
- **Motivo:** permite una sincronización futura sin reescribir los datos. Por ahora la sincronización **no** forma parte del MVP.

## ADR 13 — Motor de cálculo en el dispositivo: estudio antes de decidir · **Propuesta**
- **[P]** No se integra Python en Android sin el estudio comparativo de `arquitectura_tecnica.md §4`. Se harán prototipos medidos (tamaño del APK, arranque en frío, memoria, aislamiento y tiempo máximo).
- Mientras tanto: cálculo remoto opcional y **[P]** gráficas de funciones simples dibujadas en Flutter.

## ADR 14 — Modelo de página con capas · **Propuesta**
- **[P]** El cuaderno se organiza en **páginas de tamaño fijo** (A4, Carta e infinita) con capas: fondo, PDF, tinta y objetos (texto Markdown, fórmulas, imágenes y figuras).
- La tinta se guarda como trazos vectoriales en coordenadas de página.
- Las notas Markdown actuales se conservan como objeto "bloque de texto" (no se elimina ninguna función).

## ADR 15 — Firma propia del APK en los secretos de CI · **Propuesta**
- **[P]** El dueño genera la clave de firma fuera de CI y la guarda en los secretos de GitHub. Las compilaciones de PR o forks siguen usando la clave debug.
- Hay que hacerlo **antes** de la Etapa 2: cambiar de clave obliga a desinstalar una vez, y después de la migración eso borraría los datos locales.

## ADR 16 — Versión única del producto · **Aceptada** (Misión 003)
- Fuente única: `app/pubspec.yaml`, `version: X.Y.Z+N`. `X.Y.Z` usa versionado semántico; `N` es el número de compilación (versionCode de Android), sube en cada release de distribución y nunca se reutiliza.
- `backend/pyproject.toml` lleva la misma `X.Y.Z`. `tool/check_versions.py` lo comprueba en CI y comprueba también que el tag `vX.Y.Z` coincide en `release.yml`.
- Las releases solo se crean con tags y como **borrador**.

## ADR 17 — Autenticación del backend por token compartido · **Aceptada** (Misión 003)
- Token obligatorio en todas las rutas salvo `/health` (sin datos sensibles) y la documentación, **también desde el propio equipo**.
- El filtro de origen (loopback y redes privadas) es una defensa adicional, **no** un sustituto del token.
- Límite de 2 tareas aisladas simultáneas (503 si no hay hueco).
- El token no se incrusta en el código ni en `--dart-define` de producción; lo introduce el usuario.
- Pendiente: TLS y almacenamiento cifrado (`flutter_secure_storage`), cada uno con su propuesta.

## Decisiones aplazadas
- Sincronización (PowerSync, servidor propio o CRDT): después del MVP sin conexión.
- Reconocimiento de escritura a mano y de fórmulas (ML Kit Digital Ink, MyScript SDK u otro modelo): requiere estudiar licencias y funcionamiento sin conexión.
- Nombre del producto: **[P]** "Euler Notes" como nombre comercial y "Cuaderno Científico" como subtítulo. Pendiente de tu confirmación.
