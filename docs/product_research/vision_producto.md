# Visión de producto e identidad

> Estado: **propuesta [P]** para validar.

## Declaración
**Euler Notes es el cuaderno donde las matemáticas se escriben a mano, se leen como LaTeX y se calculan de verdad, sin conexión y sin cuenta.**

## Usuario objetivo
- **Principal:** estudiantes universitarios de Física, Matemáticas e Ingeniería con tablet Android y lápiz.
- **Secundario:** docentes e investigadores que leen artículos (PDF) y toman notas de cálculo en Linux.

## Principios de diseño
1. **Primero la página y el lápiz.** Escribir debe ser tan inmediato como en papel. El cálculo nunca interrumpe la escritura.
2. **Las matemáticas son objetos vivos.** Una fórmula puede ser tinta, LaTeX o expresión de SymPy. Se pasa de una forma a otra sin perder la original.
3. **Verificable, no "mágico".** Los resultados vienen de un motor simbólico determinista (SymPy), no de una IA que puede inventar. La IA, si llega, ayuda pero no calcula.
4. **Sin conexión y privado por defecto.** Los datos viven en el dispositivo, en SQLite. La nube es opcional.
5. **Formatos abiertos.** Exportar a PDF, Markdown y LaTeX. El usuario es dueño de sus notas.
6. **Identidad propia.** Portadas, papeles e icono dibujados por código (ADR 7), con homenajes científicos y nada de recursos de terceros.

## Diferenciadores (frente a la matriz)
| Diferenciador | Por qué importa | Ya existe |
|---|---|---|
| Bloque de cálculo SymPy en la página (derivar, integrar, resolver, simplificar, series) | Nadie tiene un CAS completo en un cuaderno de tinta | ✅ (con servidor) |
| Gráfica "viva" de una fórmula de la página | Ver la función mientras se estudia | ✅ (con servidor) |
| LaTeX editable de primera clase y teclado científico | Precisión y exportación a artículos | ✅ |
| Unidades y constantes físicas en el cálculo | Específico de Física | ❌ |
| PDF científico + nota en pantalla dividida, con recorte de ecuaciones y figuras enlazado | Flujo real de estudio de artículos | ◐ |
| Papeles científicos: milimetrado, polar, logarítmico, isométrico | Papel de laboratorio | ◐ (algunos papeles) |
| Plantillas de Física: diagrama de cuerpo libre, circuito, vectores | Ahorra tiempo en problemas | ◐ (`diagram`) |

## Identidad visual (dirección, no diseño final)
- **Nombre:** "Euler Notes" (comercial), con el subtítulo "Cuaderno Científico".
- **Tono:** académico, sobrio y cálido. Inspirado en el papel de cálculo y las pizarras, pero **sin imitar** la estética de ninguna de las apps estudiadas.
- **Motivo gráfico propio:** la identidad de Euler (e^{iπ}+1=0) y la geometría del círculo unidad, ya presente en el icono actual.
- **Accesibilidad:** contraste suficiente en tema claro y oscuro, tamaños táctiles de 48 dp o más y el lápiz como entrada principal.

## Fuera de alcance (MVP)
IA generativa, colaboración en tiempo real, tienda de plantillas y anuncios.
