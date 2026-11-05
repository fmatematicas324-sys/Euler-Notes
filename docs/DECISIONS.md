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

## ADR 10 — Almacenamiento local: Drift sobre `package:sqlite3` · **Aceptada** (Misión 014, 2026-11-05)
- **Decisión [H]:** el prototipo cumple todos los criterios en la tablet Android 13 del dueño (autoguardado 0,33 ms, trazo 0,78 ms, abrir cuaderno 2 ms, tinta de una página 9 ms, FTS5 disponible, WAL). Detalle en `product_research/prototipo_almacenamiento.md`. Se descarta el plan B (`sqlite3` directo).
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

## ADR 15 — Firma propia del APK en los secretos de CI · **Aceptada** (Misión 010)
- El dueño genera la clave de firma fuera de CI y la guarda en los secretos de GitHub. Las compilaciones de forks siguen usando la clave debug.
- La usan `ci.yml` **y** `release.yml`: el APK de comprobación es el que se instala en la tablet para probar, y con otra clave obligaría a desinstalar en cada prueba (pasó en la Misión 008).
- Gradle firma con `android/key.properties` si existe; si no, con la clave debug.
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

## ADR 18 — Superficies 3D renderizadas en el backend · **Aceptada** (Misión 008)
- Se dibujan con matplotlib (`mplot3d`) como un tipo más de `/diagram`; el cliente solo muestra el PNG, como el resto de figuras. Sin dependencias nuevas.
- Las caras se construyen a mano (`Poly3DCollection`) para descartar las que tienen vértices sin valor real, en vez de depender del trato de los NaN en `plot_surface`, que varía entre versiones.
- Imagen estática: no se puede girar. Una vista interactiva exigiría render en el cliente y se valorará con la arquitectura sin conexión (ADR 10–14).

## ADR 19 — Emparejamiento: el token se muestra solo a petición · **Aceptada** (Misión 011)
- `python -m app.pair` muestra la dirección LAN y el token (con QR) cuando el dueño lo pide en la terminal.
- El servidor **no** escribe el token en sus registros: con systemd quedaría guardado en el journal.
- El QR contiene solo el token; la cámara de la tablet lo copia sin que la app necesite permiso de cámara ni dependencias nuevas.
- El backend se instala como servicio **de usuario** de systemd (sin sudo).

## ADR 20 — Más figuras en el mismo motor · **Aceptada** (Misión 012)
- Curvas de nivel, campos vectoriales y curvas 3D son tipos de `/diagram` dibujados con matplotlib, como el resto (ADR 18). Sin dependencias nuevas.
- El campo vectorial muestra ∇·F y (∇×F)_z calculados con SymPy: la figura enseña, no solo dibuja.
- Mismo recorte por percentiles en todas las figuras para que los polos (1/r, 1/r²) no aplasten la imagen.

## ADR 21 — Borradores locales fuera de las copias de seguridad · **Aceptada** (Misión 013)
- Los borradores de notas se guardan en `shared_preferences`, el mismo archivo que la URL y el token, que está excluido de las copias de seguridad de Android (Misión 004, M3).
- Motivo: son temporales (la nota real está en el servidor y el borrador se borra al guardar) y contienen apuntes del usuario que no deben subir a la nube de Google sin que lo decida.
- La clave incluye la URL del servidor: el id de una nota solo es único dentro de un servidor.
- `android_backup_rules_test.dart` comprueba que solo `server_settings.dart` y `note_drafts.dart` escriben en ese archivo.
- Revisar en la Etapa 2: con notas locales, el almacenamiento principal sí deberá respaldarse (o exportarse).

## ADR 22 — Etapa 2 con el modelo actual de notas · **Aceptada** (Misión 015)
- Decisión del dueño: en la Etapa 2 la copia local guarda **cuadernos, notas Markdown y dibujos** como hoy. Las páginas con capas (ADR 14) se aplazan a la Etapa 3, cuando se rehaga el editor.
- Los dibujos guardan sus trazos en el mismo JSON que la app (`Stroke.toJson`); el formato `Float32` del prototipo queda para la Etapa 3.
- En la copia local, los bloques ` ```ink ` usan el UUID del dibujo local. El servidor no se modifica.
- Los PDF se importarán en una misión posterior.
- Limitación conocida: si algo se borra en el servidor después de importarlo, la copia local lo conserva hasta que exista la sincronización.

## Decisiones aplazadas
- Sincronización (PowerSync, servidor propio o CRDT): después del MVP sin conexión.
- Reconocimiento de escritura a mano y de fórmulas (ML Kit Digital Ink, MyScript SDK u otro modelo): requiere estudiar licencias y funcionamiento sin conexión.
- Nombre del producto: **[P]** "Euler Notes" como nombre comercial y "Cuaderno Científico" como subtítulo. Pendiente de tu confirmación.
