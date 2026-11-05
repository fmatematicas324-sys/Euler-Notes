# Prototipo de almacenamiento local — Misión 014 (Etapa 2)

> Fecha: 2026-11-05. Objetivo: decidir con datos la **ADR 10** (Drift sobre `sqlite3` 3.x) antes de migrar ninguna nota.
> Marcas: **[H]** comprobado · **[Hip]** sin comprobar · **[P]** propuesta.

## 1. Qué se prueba

| Pregunta | Cómo se responde |
|---|---|
| ¿Compila Drift con la generación de código (`build_runner`) en Flutter 3.47? | CI: `dart run build_runner build` antes de `flutter analyze`, `flutter test` y el APK |
| ¿Funciona `sqlite3` 3.x (con sus *build hooks* nativos) en Linux y en Android? | CI (Linux, `flutter test`) y laboratorio en la tablet (Android) |
| ¿Trae SQLite el módulo **FTS5** (búsqueda de texto)? | Prueba automática y laboratorio |
| ¿Es lo bastante rápido para el autoguardado y la tinta? | Laboratorio en la tablet, con los criterios de §2 |

**No se prueba aquí:** el esquema definitivo de páginas y capas (ADR 14), la migración desde el servidor ni la versión web (necesita `sqlite3.wasm`).

## 2. Criterios de aceptación [P]

| Medida | Criterio | Por qué |
|---|---|---|
| Autoguardado de una página (transacción propia) | ≤ 15 ms de media | Se guarda tras cada pausa al escribir; no debe notarse |
| Guardar un trazo al levantar el lápiz | ≤ 15 ms de media | Un trazo por transacción (arquitectura §3.2) |
| Abrir un cuaderno (50 páginas) | ≤ 100 ms | Sensación de apertura instantánea |
| Cargar la tinta de una página (300+ trazos) | ≤ 100 ms | Igual |
| Modo de diario | WAL | Resistencia a cierres de Android |
| FTS5 | Disponible | Búsqueda en notas (y más adelante en PDF) |

## 3. El laboratorio

- **Dónde:** icono de matraz 🧪 en la pantalla principal → «Ejecutar la prueba».
- **Qué hace:** crea 20 cuadernos con 50 páginas de ~2 KB (1.000 páginas), simula 200 autoguardados, guarda 300 trazos de 100 puntos de golpe y 100 trazos uno a uno, busca con FTS5 y mide el tamaño.
- **Seguridad:** usa una base aparte (`euler_notes_lab.sqlite`) que se **vacía al terminar**. No toca las notas ni el servidor.
- **Resultado:** lista con ✔/✘ por criterio y botón para copiar el informe.

## 4. Resultados

### CI (Linux, GitHub Actions) — run `42101112783` [H]
| Comprobación | Resultado |
|---|---|
| Versiones resueltas | `drift` 2.35.3, `drift_dev` 2.35.2, `drift_flutter` 0.3.1, `build_runner` 2.17.1, `sqlite3` 3.5.2 (`sqlite3_flutter_libs` 0.6.0+eol, ya vacío: el motor llega por los *build hooks* de `sqlite3` 3.x) |
| Generación de código | ✅ `build_runner` en 49 s (165 salidas) |
| `flutter analyze` | ✅ sin incidencias |
| Pruebas `local_database_test.dart` (6) | ✅ UUID v7, esquema y claves foráneas, tinta Float32 de ida y vuelta, banco de pruebas completo |
| FTS5 en el SQLite de `sqlite3` 3.x (Linux) | ✅ disponible |
| APK | ✅ compila y se firma con la clave estable (`650ff58d…`) |
| Tamaño del APK | **82,2 MB → 89,0 MB (+6,8 MB)**: bibliotecas nativas de SQLite para cada ABI. **[P]** Se puede reducir publicando APK por arquitectura (`--split-per-abi`), solo arm64 para la tablet |

### Tablet Android (dispositivo real)
_Pendiente: ejecutar el laboratorio y pegar aquí el informe._

## 5. Decisión

_Pendiente de los resultados en la tablet._ Si se cumplen los criterios, la ADR 10 pasa a **Aceptada** y la siguiente misión diseña el esquema definitivo y la importación desde el servidor. Si no, se prueba el plan B (`sqlite3` directo).
