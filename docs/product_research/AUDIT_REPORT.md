# Auditoría técnica — Euler Notes v0.4.0 + Misiones 008–012

> Fecha: 2026-11-05 (Misión 009). Sustituye como foto actual a la auditoría de la Misión 001; esa sigue en `DEVELOPMENT_LOG.md` como historial.
> Marcas: **[H]** hecho comprobado (código, CI o prueba real) · **[Hip]** hipótesis no verificada · **[P]** propuesta.

## 1. Resumen ejecutivo

- **[H]** Euler Notes funciona hoy en la tablet Android con el backend en Fedora: notas Markdown + LaTeX, tinta, PDF, cálculo simbólico (SymPy) y figuras (gráficas 2D, superficies 3D, curvas de nivel, campos vectoriales, curvas 3D, cuerpo libre, tiro parabólico y grafos).
- **[H]** La seguridad básica está resuelta (token obligatorio, filtro de red, límites de cálculo). Falta cifrado (TLS).
- **[H]** El mayor riesgo técnico es la **dependencia del PC**: sin backend la app no abre ni guarda notas.
- **[H]** El mayor riesgo operativo era la **firma del APK** (cada compilación usaba una clave distinta). El código ya está listo (Misión 010); falta que el dueño genere la clave.
- **[P]** Prioridad: activar la firma estable → probar la conexión cómoda (Misión 011) → decidir la Etapa 2 (sin conexión).

## 2. Inventario

| Parte | Tamaño [H] | Tecnología [H] |
|---|---|---|
| App (`app/lib`) | ~7.000 líneas Dart | Flutter 3.47.9, Riverpod 3, http, flutter_markdown_plus, flutter_math_fork, pdfrx, file_selector, shared_preferences |
| Backend (`backend/app`) | ~2.700 líneas Python | FastAPI, uvicorn, SymPy, matplotlib (Agg + mplot3d), numpy, networkx, pypdf, segno, SQLite |
| Pruebas | ~3.700 líneas Dart (134 casos declarados) · ~1.300 líneas Python (103 funciones, más casos parametrizados) | flutter_test, integration_test, pytest, httpx |
| API | 25 rutas | cuadernos, notas, dibujos, documentos PDF, `/compute`, `/plot`, `/diagram`, `/health`, `/auth/check` |

### Figuras disponibles en `/diagram` (bloque ` ```diagram ` en las notas)
| Tipo | Desde | Para qué |
|---|---|---|
| `function` | v0.3 | Análisis visual de derivar, integrar, resolver y simplificar |
| `forces` | v0.3 | Diagrama de cuerpo libre con resultante |
| `projectile` | v0.3 | Tiro parabólico (altura máxima, alcance, tiempo de vuelo) |
| `graph` | v0.3 | Grafos y redes (NetworkX) |
| `surface` | Misión 008 | Superficie z = f(x, y) con curvas de nivel en la base |
| `contour` | Misión 012 | Curvas de nivel f(x, y) = c, rellenas o en líneas |
| `vector_field` | Misión 012 | Campo F = (P, Q) con flechas o líneas de campo, y ∇·F y (∇×F)_z |
| `curve3d` | Misión 012 | Curva paramétrica r(t) en el espacio |

## 3. Estado de los problemas abiertos de la Misión 002

| # | Problema | Estado |
|---|---|---|
| 1 | Dependencia total del backend | ⏳ Abierto. Es la Etapa 2 (ADR 10–14, no autorizada). |
| 2 | Si falla un guardado, el texto queda solo en memoria | ⏳ Abierto **[Hip]**: no se ha reproducido. Ver §6. |
| 3 | Servidor sin autenticación | ✅ Token obligatorio y filtro de red (Misiones 003–004). ⏳ Falta TLS. |
| 4 | Cliente HTTP sin tiempo de espera | ✅ `ApiTimeouts` (Misión 004). |
| 5 | Cálculos simultáneos sin límite | ✅ Máximo 2 tareas aisladas, 503 si no hay hueco. |
| 6 | Firma debug distinta en cada CI | ◐ Código listo (Misión 010). Falta generar la clave y los secretos (`SIGNING.md` §0). |
| 7 | Release en cada push | ✅ Solo con tags y como borrador. |
| 8 | Nombres y versiones desalineados | ✅ Versión única 0.4.0 (ADR 16). |
| 9 | Backend solo Unix (`forkserver`, `resource`) | ⏳ Abierto; relevante solo si el cálculo pasa a Android (ADR 13). |

## 4. Seguridad

**Lo que está bien [H]**
- Token de 256 bits (`secrets.token_urlsafe(32)`), archivo con permisos 0600, comparación en tiempo constante.
- Filtro de origen explícito (loopback, RFC 1918, link-local, ULA); se rechazan cabeceras de proxy.
- Expresiones validadas antes de evaluarse y cálculo en subprocesos aislados con límite de memoria y de tiempo.
- El token no aparece en los registros del servidor (Misión 011): `python -m app.pair` lo muestra solo a petición.
- En Android, la URL y el token quedan fuera de las copias de seguridad.

**Riesgos [H/Hip]**
| Riesgo | Gravedad | Comentario |
|---|---|---|
| HTTP sin cifrar en la Wi-Fi | Media | En una red ajena, alguien podría leer el token. **[P]** Usar solo redes de confianza; estudiar TLS autofirmado con huella fijada en la app. |
| Token compartido por error | Baja–media | Pasó en este chat. Ahora hay `python -m app.pair --rotar` y una guía (`CONEXION.md` §3). |
| Token en `shared_preferences` sin cifrar | Baja | Fuera de copias de seguridad; **[P]** `flutter_secure_storage` (estudio en `SERVER_SECURITY.md`). |
| Pérdida de la clave de firma | Alta (cuando exista) | Tres copias (`SIGNING.md` §2.2). Sin ella, otra desinstalación para todos. |

## 5. Calidad y pruebas

- **[H]** CI en cada push: `ruff check`, `ruff format --check`, `pytest` (Python 3.12 y 3.13), `flutter analyze`, `flutter test`, comprobación de versiones y APK.
- **[H]** Primera prueba real en la tablet: superficies 3D (Misión 008, 2026-11-05).
- **[H]** `pytest` ejecutado en Fedora por el dueño (41 pruebas de diagramas en verde).
- **Lagunas:**
  - **[H]** `integration_test/` no se ejecuta en CI (necesita dispositivo o navegador con backend).
  - **[H]** Las figuras se prueban por «devuelve un PNG válido», no por su contenido. **[P]** Pruebas de imagen de referencia solo para casos clave, con tolerancia.
  - **[Hip]** Nadie ha medido el tiempo de las figuras más pesadas en el PC (curvas de nivel 160×160, líneas de campo). El límite por cálculo es de 5 s (`EULER_COMPUTE_TIMEOUT`).

## 6. Riesgos priorizados y recomendaciones [P]

| Prioridad | Recomendación | Esfuerzo |
|---|---|---|
| 1 | Generar la clave y los secretos (`SIGNING.md` §0) y hacer la **última** desinstalación | 20 min del dueño |
| 2 | Instalar el servicio y reservar la IP en el router (`CONEXION.md`) | 15 min del dueño |
| 3 | Reproducir el problema 2 (guardado fallido): apagar el servidor mientras se escribe y comprobar qué se pierde; si se confirma, guardar un borrador local | 1 misión corta |
| 4 | Ensayo de la Etapa 2: prototipo Drift en la tablet (ya planificado en `TASKS.md`) | 1 día |
| 5 | TLS en la red local o, como mínimo, aviso visible en la app cuando se usa HTTP | 1 misión |
| 6 | Medir tiempos de las figuras en el PC y ajustar mallas si alguna roza los 5 s | 30 min |

## 7. Comandos de verificación

```bash
cd backend && .venv/bin/pytest -q && .venv/bin/ruff check . && .venv/bin/ruff format --check .
cd app && flutter analyze && flutter test
```
