# Seguridad del servidor (backend)

> Estado: implementado en la Etapa 0 (Misión 003). Marcas: **[H]** hecho comprobado · **[C]** conocimiento previo no verificado · **[Hip]** hipótesis · **[P]** propuesta.

## 1. Qué protege y qué no

| Capa | Qué hace | Qué **no** hace |
|---|---|---|
| **Token de acceso** (`Authorization: Bearer`) | Toda petición salvo `/health` y la documentación de la API exige el token, **también desde el propio equipo** | No cifra nada. Si alguien lo obtiene, tiene acceso completo |
| **Origen de la conexión** | Rechaza (403) conexiones que no vengan del propio equipo ni de una red privada (10/8, 172.16/12, 192.168/16, fc00::/7, enlace local) | **No sustituye a la autenticación**: cualquier dispositivo de tu WiFi pasa este filtro y solo lo frena el token |
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
.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000   # 0.0.0.0 solo si lo usará la tablet
```
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
- `ipaddress.is_private` también considera privadas algunas redes reservadas (p. ej. de documentación) **[H, Python 3.13]**. No afecta al token.
