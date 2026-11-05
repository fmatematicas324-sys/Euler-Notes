# Priorización de funciones

> Método: **MoSCoW** + puntuación simple **Valor (1–5) × Confianza (1–5) / Esfuerzo (1–5)**. Las puntuaciones son estimaciones **[Hip]** para discutir.

## MVP "tablet sin conexión" (v0.5–v0.7)
| # | Función | MoSCoW | V | C | E | Puntuación | Reutiliza |
|---|---|---|---|---|---|---|---|
| 1 | Almacenamiento local SQLite (cuadernos, notas, tinta, documentos) | Must | 5 | 5 | 4 | 6,3 | Modelos de `domain/`, esquema del backend |
| 2 | Guardado automático fiable (cierre o pausa de la app) | Must | 5 | 5 | 2 | 12,5 | Lógica de `note_editor_screen` |
| 3 | Firma propia del APK (antes del 1) | Must | 4 | 5 | 1 | 20 | — |
| 4 | Páginas A4/Carta con zoom y desplazamiento | Must | 5 | 4 | 4 | 5 | `paper_background`, `InkCanvas` |
| 5 | Tinta vectorial por página + lazo + borrador parcial | Must | 5 | 4 | 4 | 5 | `Stroke`, `widthForPressure`, caché `Picture` |
| 6 | Objetos en la página: texto Markdown/LaTeX, fórmula, imagen, figura | Must | 5 | 4 | 4 | 5 | `markdown_preview`, `MathFormula`, `FigureView` |
| 7 | Anotar sobre PDF (capa de tinta por página) | Must | 5 | 4 | 3 | 6,7 | `document_viewer_screen`, pdfrx |
| 8 | Cálculo remoto opcional con degradación clara | Must | 4 | 5 | 2 | 10 | `ApiClient`, `compute_panel` |
| 9 | Gráficas simples en Flutter sin conexión | Should | 4 | 3 | 3 | 4 | `PlotSpec` |
| 10 | Búsqueda en títulos y texto (SQLite FTS5) | Should | 4 | 4 | 2 | 8 | — |
| 11 | Exportar página o cuaderno a PDF | Should | 4 | 4 | 3 | 5,3 | — |
| 12 | Secciones dentro del cuaderno | Should | 3 | 4 | 2 | 6 | — |
| 13 | Pantalla dividida PDF + nota y recorte enlazado | Could | 4 | 3 | 4 | 3 | — |
| 14 | Cálculo SymPy en el dispositivo (Python embebido) | Could → según el estudio | 5 | 2 | 5 | 2 | `backend/app/services` |
| 15 | Unidades y constantes físicas | Could | 4 | 3 | 3 | 4 | SymPy `physics.units` |
| 16 | Fórmula manuscrita → LaTeX | Could (estudio) | 5 | 2 | 5 | 2 | — |
| 17 | Audio sincronizado con la tinta | Won't (MVP) | 3 | 3 | 4 | 2,3 | — |
| 18 | Sincronización | Won't (MVP) | 4 | 3 | 5 | 2,4 | ADR 12 lo prepara |
| 19 | IA generativa | Won't (MVP) | 2 | 2 | 4 | 1 | — |

## Orden propuesto
**Etapa 0** (3) → **Etapa 2** (1, 2, 8) → **Etapa 3** (4, 5, 6, 7) → 10, 11, 12, 9 → estudios 14 y 16.

Cada etapa termina con un APK probado en una tablet real.
