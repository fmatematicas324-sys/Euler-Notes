# Euler Notes — Tareas

Estado: ⏳ pendiente de aprobación · 🔜 aprobada, sin empezar · 🚧 en curso · ✅ hecha.
**Nada de esta lista está implementado.** Esta lista es el plan propuesto en la Misión 002.

---

## Etapa 0 — Limpieza controlada (plan; ninguna acción ejecutada)

### 0.1 Unificar nombres y versiones ✅ (Misión 003, paso B; ADR 16)
| Acción | Detalle | Riesgo |
|---|---|---|
| Elegir el nombre | **[P]** "Euler Notes" como nombre comercial y "Cuaderno Científico" como descripción | Bajo. Requiere tu decisión. |
| Una sola fuente de versión | `app/pubspec.yaml` para la app. El backend lee su versión de `pyproject.toml` con `importlib.metadata` en lugar de la constante `VERSION` | Bajo. `/health` cambia el valor que devuelve. |
| Textos visibles | Título web (`index.html`, `manifest.json`), ejecutable de Linux, README, CLAUDE.md | Bajo |
| **No tocar** `applicationId` (`dev.eulernotes.euler_notes`) | Cambiarlo crea "otra app" en Android | Alto si se cambia |

### 0.2 Ramas y tags ◐ workflow ✅ (paso A) · PR preparado sin fusionar · tags históricos ⏳ (decisión provisional: v0.1.0→`f051026`, v0.2.0→original de Fedora si existe, v0.3.0→`d397094`; no crear todavía)
**Hechos [H]:**
- `master` = `df2c80d`.
- La rama de trabajo va por delante con `b14fcb2` y los documentos.
- Solo existe el tag `v0.4.0`, que apunta a `b14fcb2` (fuera de `master`).

| Acción propuesta | Riesgo / mitigación |
|---|---|
| Abrir un PR de la rama a `master` y fusionar **sin squash** (merge commit o fast-forward) | Con squash, el tag `v0.4.0` apuntaría a un commit fuera de `master` |
| Recrear `v0.1.0`, `v0.2.0` y `v0.3.0` como tags anotados sobre los commits de cierre de cada fase (candidatos: `f051026` para v0.1.0, `9c1b0b5` para v0.2.0 y `d397094` para v0.3.0) | Etiquetar el commit equivocado. Mitigación: revisar juntos la lista antes de crearlos |
| Cambiar el workflow: compilar en cada push (solo artefacto) y **publicar release solo con tag `v*` o ejecución manual** | **[H]** Hoy cada push que toca `app/` vuelve a publicar en `v0.4.0` y puede sobrescribir el APK ya publicado |
| Política de ramas: `master` estable, `feature/*` y PR obligatorio | Ninguno |

### 0.3 pytest en GitHub Actions ✅ (paso A: `ci.yml`, Python 3.12 y 3.13 + Ruff)
- **[P]** Añadir un job `backend` con Python 3.12 y 3.13: `pip install -e "backend[dev]"`, `ruff check` y `pytest`.
- Riesgos:
  - **[Hip]** `forkserver` y `RLIMIT_AS` funcionan en `ubuntu-latest` (es Linux), pero hay que comprobarlo en el primer run.
  - **[Hip]** Las pruebas de gráficas pueden depender de las fuentes de matplotlib.
  - Duración estimada **[Hip]**: 2–4 min.
- Añadir también Flutter `analyze` y `test` como job de PR, separado del de compilar el APK.

### 0.4 Firma del APK ◐ documentada en `docs/SIGNING.md` (estado, respaldo y migración); clave y `build.gradle.kts` ⏳ sin tocar
1. Tú generas una clave en tu equipo: `keytool -genkey -v -keystore euler-upload.jks -keyalg RSA -keysize 4096 -validity 10000 -alias upload`.
2. La subes a los secretos de GitHub: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` y `ANDROID_KEY_PASSWORD`.
3. `build.gradle.kts` lee `key.properties`, que se crea en CI. Si no existe, usa la firma debug.

**Riesgos:**
- Si se pierde la clave, no se puede actualizar la app nunca más. Guarda una copia de seguridad fuera de GitHub.
- La primera instalación con la clave nueva exige desinstalar la v0.4.0. Hoy no se pierde nada, porque los datos viven en el PC.
- **No subas nunca la clave al repositorio** (`.gitignore` ya excluye `*.jks` y `key.properties`).

### 0.5 Tiempos de espera HTTP ✅ (paso C)
- **[H]** Todas las peticiones pasan por `ApiClient._send`, así que hay un solo punto de cambio.
- **[P]** Añadir `.timeout()` por tipo de petición:

| Tipo | Tiempo |
|---|---|
| `/health` | 3 s |
| CRUD | 10 s |
| `/compute` | 15 s (el servidor corta a los 5 s) |
| `/plot` y `/diagram` | 20 s |
| Subida de PDF | 120 s |

- Convertir `TimeoutException` en `ApiException` con un mensaje en español, y añadir pruebas con `FakeBackend`.
- Riesgos:
  - Cortar subidas grandes en una WiFi lenta.
  - ~~`http` 1.6 no cancela la petición~~ **Corregido (Misión 004, M2):** era incorrecto. `http` 1.6.0 incluye `AbortableRequest`/`abortTrigger`, que `IOClient` y `BrowserClient` respetan. `ApiClient` lo usa: al agotarse el tiempo o cancelar, la conexión se cierra (comprobado con sockets reales en `test/api_client_cancel_test.dart`).

### 0.6 Seguridad del servidor ✅ token + filtro de origen + límite de tareas (paso D; ADR 17). TLS y `flutter_secure_storage` ⏳ con propuesta aparte (`docs/SERVER_SECURITY.md`)
**Hechos [H]:**
- Por defecto escucha en `127.0.0.1`, pero la guía de Android indica `--host 0.0.0.0`.
- No pide autenticación y no usa TLS.
- CORS solo protege a los navegadores, no a otros clientes.
- No hay límite de cálculos simultáneos.
- Los PDF se limitan a 30 MB.

| Propuesta | Esfuerzo | Riesgo |
|---|---|---|
| Token compartido: se genera al arrancar, se muestra en consola (y como QR), y la app lo envía en `Authorization: Bearer` | Bajo | Si alguien lo ve, tiene acceso. Mitigación: regenerarlo cuando se quiera |
| Rechazar IPs que no sean privadas (RFC 1918) | Bajo | Ninguno |
| Semáforo de cálculos simultáneos (p. ej. 2) con respuesta 429/503 | Bajo | Cola visible para el usuario |
| TLS con certificado autofirmado fijado en la app | Medio | Complicado de configurar para el usuario |
| Con la ADR 11, el servidor deja de guardar datos: el riesgo baja a "usar CPU" | — | — |

> **[H]** El `network_security_config` de Android no puede permitir texto plano por rango de IP, solo por dominio. Mientras no haya TLS, el permiso general seguirá siendo necesario.

---

## Etapa 1 — Competencia e identidad ✅ (documentada)
Ver `product_research/`. Falta tu validación de la visión y de la priorización.

## Etapa 2 — Arquitectura sin conexión ⏳ (no autorizada)
- [ ] Prototipo: Drift + sqlite3 3.x en Android, Linux y Web (un día).
- [ ] Interfaces de repositorio (`NotebooksRepository`, `NotesRepository`, `DrawingsRepository`, `DocumentsRepository`) con implementación local; la remota se mantiene.
- [ ] Esquema local versionado (ADR 12) y pruebas de migración.
- [ ] Guardado automático fiable: escribir al terminar cada trazo, texto con espera de 800 ms, y guardado forzado en `AppLifecycleState.paused`.
- [ ] PDF copiados a la carpeta de la app.
- [ ] Importar los datos desde un backend existente.
- [ ] Estudio de Python en el dispositivo (ADR 13): prototipos de `serious_python` y Chaquopy.

## Etapa 3 — Lienzo científico ⏳ (no autorizada)
Ver `product_research/arquitectura_tecnica.md §5`.
