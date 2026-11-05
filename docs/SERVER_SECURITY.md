# Seguridad del servidor (backend)

> Estado: implementado en la Etapa 0 (Misión 003). Marcas: **[H]** hecho comprobado · **[C]** conocimiento previo no verificado · **[Hip]** hipótesis · **[P]** propuesta.

## 1. Qué protege y qué no

| Capa | Qué hace | Qué **no** hace |
|---|---|---|
| **Token de acceso** (`Authorization: Bearer`) | Toda petición salvo `/health` y la documentación de la API exige el token, **también desde el propio equipo** | No cifra nada. Si alguien lo obtiene, tiene acceso completo |
| **Origen de la conexión** | Acepta solo la IP del socket en una lista explícita: loopback (127/8, ::1), RFC 1918 (10/8, 172.16/12, 192.168/16), link-local (169.254/16, fe80::/10) y ULA (fc00::/7). Rechaza siempre Teredo, 6to4, multicast, broadcast y direcciones no especificadas, aunque estén en `EULER_ALLOWED_NETWORKS`. IPv4-mapped se evalúa como su IPv4. Rechaza (403) peticiones con `X-Forwarded-For`, `Forwarded` o `X-Real-IP` | **No sustituye a la autenticación**: cualquier dispositivo de tu WiFi pasa este filtro y solo lo frena el token |
| **Límite de tareas simultáneas** | Como máximo 2 cálculos, gráficas o análisis de PDF a la vez; si no hay hueco en 2 s responde 503 `server_busy` | No limita el número de peticiones baratas (CRUD) |
| **CORS** | Solo los orígenes `localhost` y `127.0.0.1` pueden leer respuestas desde un navegador | No protege frente a clientes que no son navegadores |

### ⚠️ Sin TLS, el token viaja sin cifrar
El servidor usa HTTP. Cualquiera que pueda capturar el tráfico de tu red (WiFi abierta, router comprometido, otro equipo en modo monitor) **puede leer el token y las notas**. Mientras no haya TLS:
- Usa el servidor solo en redes de confianza (tu casa), nunca en WiFi pública.
- Si sospechas que el token se filtró, **regenéralo** (§3.3).
- TLS requiere una propuesta independiente (pendiente).

## 2. Configuración

| Variable | Por defecto | Para qué |
|---|---|---|
| `EULER_API_TOKEN` | — | Fija el token (mínimo 16 caracteres). Si no existe, se usa el archivo `api_token` |
| `EULER_ALLOWED_NETWORKS` | — | Redes extra permitidas, en CIDR separado por comas (p. ej. `100.64.0.0/10` para Tailscale) |
| `EULER_MAX_PARALLEL_TASKS` | `2` | Tareas aisladas simultáneas |
| `EULER_TASK_QUEUE_TIMEOUT` | `2` | Segundos de espera de un hueco antes del 503 |

Las variables antiguas `CUADERNO_*` siguen funcionando; si existen las dos, gana `EULER_*`.

## 3. Procedimientos

### 3.1 Primer arranque
```bash
cd backend
.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000 --no-proxy-headers   # 0.0.0.0 solo si lo usará la tablet
```
- `--no-proxy-headers`: uvicorn no debe reescribir el origen con `X-Forwarded-For`. Por defecto lo hace si la conexión viene de 127.0.0.1 **[H, uvicorn]**. Aunque se olvide la opción, el backend rechaza cualquier petición con cabeceras de proxy (403 `forwarded_not_allowed`), así que el origen siempre sale de la IP del socket. Consecuencia: **no se puede usar detrás de un proxy inverso** sin cambiar esta política.
- Si no hay `EULER_API_TOKEN`, el servidor crea `backend/data/api_token` (32 bytes aleatorios, `secrets.token_urlsafe`, permisos `0600`).
- La consola indica **dónde** está el token, pero **no lo muestra** **[H]** (comprobado: el token no aparece en el log).
- `backend/data/` está en `.gitignore`: el token nunca se sube al repositorio.

### 3.2 Configurar un dispositivo (tablet, otro PC, navegador)
1. En el PC del servidor, mira el token: `cat backend/data/api_token`.
2. En la app: icono de servidor → **Dirección** (`http://IP-DEL-PC:8000`) y **Token de acceso** (oculto por defecto; botón para mostrarlo).
3. Pulsa **Probar conexión**. La app llama a `/health` (público) y después a `/auth/check` (con token): debe decir "Conectado y autenticado".
4. **Guardar.**

Evita enviar el token por canales que se guarden en la nube (chat, correo). **[P]** Más adelante: mostrar un código QR en la consola del servidor para escanearlo desde la tablet.

### 3.3 Cambiar (rotar) el token
1. Para el servidor.
2. Borra `backend/data/api_token` (o cambia `EULER_API_TOKEN`).
3. Arranca el servidor: genera uno nuevo.
4. Actualiza el token en cada dispositivo (§3.2). Los que tengan el antiguo recibirán 401.

### 3.4 Pruebas de integración
Solo en pruebas, el token se pasa con `--dart-define=API_TOKEN=...`. **La app nunca lee el token de `--dart-define`**: el código de `lib/` solo lo obtiene del diálogo del servidor.

## 4. Almacenamiento del token en la app

### Copias de seguridad de Android (Misión 004, M3)
| Qué | ¿Se respalda? | Dónde se configura |
|---|---|---|
| `shared_prefs/FlutterSharedPreferences.xml` (**solo** `server_url` y `server_token`) | **No**: ni en la nube ni en la transferencia entre dispositivos | `res/xml/backup_rules.xml` (Android 6–11, `android:fullBackupContent`) y `res/xml/data_extraction_rules.xml` (Android 12+, `android:dataExtractionRules`) |
| Cualquier otro dato de la app (hoy no hay; en el futuro, la base de datos local) | Sí (comportamiento por defecto de Android) | — |

- Se excluye el archivo entero porque Android no permite excluir claves sueltas. Al restaurar en otro dispositivo hay que volver a escribir **la dirección y el token** (§3.2).
- `app/test/android_backup_rules_test.dart` comprueba las reglas, y que ese archivo solo guarda esas dos claves.
- La API usada es `SharedPreferences.getInstance()`, que en Android guarda en `FlutterSharedPreferences.xml` **[H, código de shared_preferences_android 2.5.4]**. Si algún día se usa `SharedPreferencesAsync` (DataStore), habrá que excluir también su archivo.
- **No verificado en un dispositivo:** comprobar con `adb shell bmgr backupnow dev.eulernotes.euler_notes` y revisando el contenido de la copia. Aquí no hay SDK de Android.

**Hoy [H]:** el token se guarda en `shared_preferences`, igual que la URL del servidor. **No está cifrado**:
- Android: un archivo XML en el directorio privado de la app. Otras apps no pueden leerlo sin root, pero sí una copia de seguridad o un dispositivo rooteado **[C]**.
- Linux: un archivo JSON en `~/.local/share/<app>/` legible por tu usuario **[C]**.
- Web: `localStorage` del navegador **[C]**.

### Investigación: `flutter_secure_storage`
| Aspecto | Dato |
|---|---|
| Versión | 11.2.0, publicada el 2026-09-16 **[H, pub.dev]** |
| Plataformas | Android, iOS/macOS, Linux, Windows y Web (paquetes por plataforma) **[H, pub.dev]** |
| Android | Cifra con claves del **Android Keystore** **[C]**. Riesgo: si el sistema invalida la clave (restaurar copia en otro dispositivo, cambiar bloqueo de pantalla en algunos fabricantes), el valor no se puede leer y hay que volver a pedir el token **[C]** |
| Linux | Usa **libsecret** (Secret Service: GNOME Keyring o KWallet) **[C]**. Compilar requiere `libsecret-1-dev`, y en ejecución hace falta un llavero activo; en escritorios mínimos puede fallar **[C/Hip]** |
| Web | Cifra con WebCrypto, pero la clave también vive en el navegador: **no es un almacenamiento seguro real** **[C]** |
| Coste | Una dependencia nueva con código nativo; cambios en CI (paquete de sistema para Linux) |

**Propuesta [P] (requiere tu aprobación, no implementada):**
- Adoptar `flutter_secure_storage` **en Android y Linux**, con *fallback* explícito: si el llavero no está disponible, avisar y pedir el token en cada arranque (sin guardarlo en texto plano).
- En Web, no guardar el token: pedirlo en cada sesión.
- Migración: al primer arranque, mover el token de `shared_preferences` al almacén seguro y borrarlo del primero.
- Pruebas: interfaz `TokenStore` en Dart con una implementación falsa para los tests de widgets.

## 5. Riesgos conocidos
- Token sin cifrar en tránsito (sin TLS) y en reposo (`shared_preferences`).
- Un solo token compartido: no distingue dispositivos ni permite revocar uno solo.
- `/docs` y `/openapi.json` son públicos: no contienen datos del usuario, pero revelan la estructura de la API (ya es pública en el repositorio).
- La validación de origen se basa en la IP del socket. Detrás de un proxy inverso vería la IP del proxy (hoy no se usa proxy).
- ~~`ipaddress.is_private` acepta Teredo y 6to4~~ **Corregido (Misión 004, M1):** se usa una lista explícita de redes.
