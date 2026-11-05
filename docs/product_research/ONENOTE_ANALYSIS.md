# Análisis de experiencia de usuario — hacia un cuaderno científico privado y ligero

> Fecha: 2026-11-05 (Misión 009). Investigación **solo funcional**: no se copian código, iconos, textos ni interfaces.
> Marcas: **[W]** verificado en la web en esta misión o en la Misión 002 (fuentes al final y en cada informe) · **[C]** conocimiento previo no verificado · **[H]** hecho de Euler Notes · **[Hip]** hipótesis · **[P]** propuesta.
> Informes detallados por app (Misión 002): `onenote.md`, `goodnotes.md`, `myscript_notes.md` (antes Nebo), `flexcil.md`, `noteshelf.md`, `kilonotes.md`. Este documento **no los repite**: los resume desde una sola pregunta y añade Obsidian, que faltaba.

## 1. La pregunta

¿Qué experiencia necesita un estudiante de Física o Matemáticas que quiere un cuaderno **privado** (sus datos en sus dispositivos, sin cuenta obligatoria), **ligero** (rápido en una tablet Android normal) y **científico** (fórmulas, cálculo y figuras de verdad)?

## 2. Qué hace bien cada referente (en una línea)

| App | Lo que mejor resuelve | Lo que le falta para nuestro caso |
|---|---|---|
| **OneNote** | Organización en cuaderno → sección → página; asistente de matemáticas con gráficas [W] | Cuenta y nube obligatorias [C]; no es un CAS real [C] |
| **Goodnotes** | «Papel digital»: páginas fijas, plantillas, lazo y convertir [C] | Funciones de IA/matemáticas llegan antes o solo a Apple [W]; suscripción |
| **MyScript Notes (Nebo)** | Escribir una fórmula a mano y obtener LaTeX editable [W] | Solo resuelve cálculos sencillos [W]; motor cerrado y de pago para terceros [C] |
| **Flexcil** | Leer un PDF y tomar notas al lado, con enlace al origen [W/C] | Sin herramientas matemáticas [C]; valoración media en Android [W] |
| **Obsidian** | **Privacidad y formato abierto**: carpeta local de archivos Markdown, gratis para uso personal, sin telemetría [W]; LaTeX con `$…$` y `$$…$$` [C]; plugins [W] | Sin escritura a mano nativa [C]; el cálculo depende de plugins [C]; no está pensado para el lápiz |

## 3. Obsidian (nuevo)

- **Modelo [W]:** la app es gratis y sin límites, sin registro. Los extras son opcionales: Sync (4 USD/mes al año, cifrado de extremo a extremo AES-256 e historial de versiones), Publish (8 USD/mes al año) y licencia comercial voluntaria (50 USD/usuario/año).
- **Privacidad [W]:** la página oficial afirma que los datos se guardan en el dispositivo, que Obsidian no puede acceder a ellos y que las apps no recogen telemetría.
- **Android [W]:** unos 6,3 M de instalaciones y 4,3★ con ~19 mil valoraciones; actualizada en octubre de 2026 (agregador). Se describe como una base de conocimiento sobre «una carpeta local de archivos Markdown de texto plano», con barra de herramientas personalizable, vista de grafo, plugins de la comunidad y barra lateral fijable en tablets.
- **Matemáticas [C]:** renderiza LaTeX en línea y en bloque; los diagramas Mermaid van en bloques de código. Hay plugins de la comunidad para escribir fórmulas, por ejemplo con MathType [W].

**Qué aprendemos [P]**
1. **Los datos del usuario en archivos que él entiende.** Markdown en una carpeta es la mejor garantía de privacidad y de que las notas sobreviven a la app. Euler Notes ya guarda las notas como Markdown con bloques ` ```plot `, ` ```diagram ` e ` ```ink ` [H]: es el mismo principio y conviene conservarlo en la Etapa 2.
2. **Bloques de código como «objetos inteligentes».** Obsidian (Mermaid) y Euler Notes (` ```diagram `) coinciden en que el texto es la fuente y la figura se genera. Es portable y se puede revisar con git.
3. **Gratis para uso personal y sin cuenta** genera confianza. El cifrado y la sincronización pueden ser opcionales.

## 4. Principios de experiencia para Euler Notes [P]

1. **Privado por defecto.** Sin cuenta. Los datos en la tablet (Etapa 2) o en tu PC (hoy). Ningún servicio externo sin permiso explícito.
2. **El texto es la fuente; la figura, una vista.** Cada figura nace de un bloque legible (` ```diagram `). Se puede copiar, versionar y exportar sin perder información.
3. **Lápiz y teclado conviven.** Tinta para pensar y dibujar (como Goodnotes), texto y LaTeX para pasar a limpio (como Obsidian). Ninguno de los dos debe ser ciudadano de segunda.
4. **El cálculo ayuda, no sustituye.** Como el enfoque de «pistas» de Goodnotes: mostrar pasos, divergencia y rotacional, puntos críticos… para entender, no solo el resultado.
5. **Ligero de verdad.** Abrir una nota en menos de un segundo en la tablet; las figuras pesadas se calculan aparte y se cachean.
6. **Leer y anotar a la vez.** PDF y nota lado a lado (Flexcil), con recortes que enlazan al origen.

## 5. Funciones recomendadas, priorizadas [P]

| Prioridad | Función | Inspirada en | Encaja con |
|---|---|---|---|
| Alta | **Funcionar sin el PC** (notas locales, Etapa 2) | Obsidian | Principio 1; problema abierto 1 de la auditoría |
| Alta | **Plantillas de figuras visibles** en un menú (ya existen 8) y vista previa en vivo al escribir el bloque | Obsidian (Mermaid), MyScript (objetos) | Principio 2 |
| Alta | **Páginas fijas A4/Carta** para tinta, con fondos cuadriculado/punteado | Goodnotes, Kilonotes | Principio 3; impresión y exportación a PDF |
| Media | **Lazo** (seleccionar, mover y escalar tinta) | Goodnotes, OneNote | Principio 3 |
| Media | **PDF + nota en pantalla dividida**, con recorte enlazado | Flexcil | Principio 6 |
| Media | **Exportar la carpeta de notas** como Markdown + imágenes | Obsidian | Principios 1 y 2 |
| Baja | Fórmula manuscrita → LaTeX | MyScript, OneNote | Requiere estudio de licencias y de modelos sin conexión (decisión aplazada) |
| Baja | Sincronización cifrada opcional | Obsidian Sync | Después del MVP sin conexión |

## 6. Qué **no** hará Euler Notes

- No copiará pantallas, iconos, gestos patentados ni textos de ninguna de estas apps.
- No exigirá cuenta ni nube para lo básico.
- No mostrará anuncios dentro del cuaderno.

## 7. Límites de este análisis

- **[H]** No se instalaron ni probaron las apps en esta misión. Antes de diseñar cada pantalla conviene probarlas en la tablet.
- **[W]** Varias cifras vienen de agregadores (instalaciones, valoraciones); se usan como orden de magnitud.

## Fuentes (Misión 009)
- [Obsidian — precios (página oficial)](https://obsidian.md/ro/pricing)
- [AppGoblin — Obsidian para Android](https://appgoblin.info/apps/md.obsidian)
- [Obsidian — plugin de la comunidad MathType](https://community.obsidian.md/plugins/mathtype)
- Fuentes de OneNote, Goodnotes, MyScript Notes y Flexcil: ver cada informe de la Misión 002.
