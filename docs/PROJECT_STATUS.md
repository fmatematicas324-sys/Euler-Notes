# Euler Notes — Estado del proyecto

> Actualizado: 2026-11-05 (Misión 002). Fuente: auditoría de la Misión 001 y revisión de esta misión.
> Marcas: **[H]** hecho comprobado · **[Hip]** hipótesis no verificada · **[P]** propuesta.

## 1. Resumen
- **[H]** Versión de la app: `0.4.0+4` (`app/pubspec.yaml`). APK publicado como pre-release `v0.4.0` en GitHub (78 MB, firma debug de CI).
- **[H]** Arquitectura actual: cliente Flutter **sin almacenamiento propio** + backend FastAPI/SQLite/SymPy en un PC. Sin backend la app no puede abrir ni guardar notas.
- **[H]** Objetivo aprobado (Misión 002): funcionar **sin conexión y sin PC**. La migración **no está autorizada todavía**; ver `product_research/arquitectura_tecnica.md`.

## 2. Código
| Parte | Tamaño aprox. [H] | Tecnología [H] |
|---|---|---|
| `app/lib` | ~6.000 líneas Dart | Flutter 3.47.9, Riverpod 3, http, flutter_math_fork, flutter_markdown_plus, pdfrx, file_selector, shared_preferences |
| `backend/app` | ~2.400 líneas Python | FastAPI, uvicorn, SymPy, matplotlib, numpy, networkx, pypdf, sqlite3 (stdlib) |
| Pruebas | ~3.700 líneas | flutter_test, integration_test, pytest, httpx |

Funciones (`app/lib/features`): `notebooks`, `notes`, `compute`, `plot`, `documents`, `ink`, `symbols`.

## 3. Pruebas
| Suite | Estado | Cómo se comprobó |
|---|---|---|
| `flutter analyze` | ✅ sin incidencias | **[H]** ejecutado en la Misión 001 y en GitHub Actions (run 42020254153) |
| `flutter test` (229) | ✅ pasan | **[H]** ídem |
| `pytest` backend | ❓ no ejecutado en estas misiones | Requiere instalar dependencias (no autorizado). El `DEVELOPMENT_LOG` dice que pasaban. |
| `integration_test/` | ❓ no ejecutado | Necesita un dispositivo o un navegador con el backend |
| Prueba en dispositivo Android real | ❌ nunca | **[H]** no hay registro |

## 4. Git
- **[H]** `master` = `df2c80d`. La rama `ccr-e7bab30d-67f6go` va por delante con el commit del APK (`b14fcb2`) y la documentación de las Misiones 001 y 002. **No está fusionada.**
- **[H]** El único tag remoto es `v0.4.0` (→ `b14fcb2`, fuera de `master`). Los tags `v0.1.0`–`v0.3.0` que menciona la documentación no existen en el remoto.
- **[Hip]** Esos tags se crearon solo en el equipo local del autor y nunca se subieron.

## 5. Problemas abiertos (priorizados)
> Actualización Misión 003: resueltos el 3 (token + filtro de origen; falta TLS), el 4 (tiempos de espera), el 5 (límite de 2 tareas), el 7 (releases solo con tags y como borrador) y el 8 (versión única 0.4.0, ADR 16). El 6 está documentado en `docs/SIGNING.md`, sin cambiar la firma.

1. **[H]** Dependencia total del backend: sin datos locales.
2. **[H]** Si falla un guardado, el texto queda solo en memoria. **[Hip]** Si se cierra la app sin conexión, se pierde.
3. **[H]** El servidor no tiene autenticación ni TLS. Al usar `--host 0.0.0.0`, cualquiera en la red local puede leer, borrar y subir PDF.
4. **[H]** El cliente HTTP no tiene tiempo de espera (`ApiClient._send`).
5. **[H]** El servidor no limita los cálculos simultáneos: cada petición crea un proceso con hasta 1 GiB.
6. **[H]** El APK se firma con una clave debug distinta en cada compilación de CI, así que las actualizaciones exigen desinstalar.
7. **[H]** El workflow publica la release en **cada push** que toca `app/`, reutilizando el tag `v0.4.0` (la versión del pubspec).
8. **[H]** Nombres y versiones desalineados: app `0.4.0`, `config.py` `0.3.0-dev`, `pyproject.toml` `0.1.0`; "Cuaderno Científico" frente a "Euler Notes".
9. **[H]** El servidor usa `forkserver` y `resource` (solo Unix), así que no puede llevarse tal cual a Android.

## 6. Próximo paso
Esperando aprobación de las acciones de la **Etapa 0** (`TASKS.md`) y de las decisiones propuestas en `DECISIONS.md` (ADR 10–15).
