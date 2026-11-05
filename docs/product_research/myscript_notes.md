# MyScript Notes (antes Nebo)

**Tipo:** cuaderno de escritura a mano con **reconocimiento en tiempo real**. El documento se reorganiza ("reflujo") como texto, pero conserva la tinta. **[C]**
**Cambio de nombre [W]:** Nebo pasó a llamarse MyScript Notes en septiembre de 2025.
**Plataformas [C/W]:** Android, iOS y Windows. La versión 7.4 permite usarla en varios dispositivos con una cuenta MyScript.
**Modelo [W]:** la página oficial menciona "lifetime access guaranteed" para los usuarios de Nebo. Hay que verificar las condiciones actuales.

## Funciones relevantes
- **Matemáticas manuscritas [W]:**
  - Seleccionar con lazo y convertir.
  - Editar con el lápiz y volver a convertir.
  - Copiar como **LaTeX** o imagen.
  - Ecuaciones de varias líneas y matrices.
  - Resolver cálculos sencillos.
- **Objetos inteligentes [W]:** bloques de matemáticas y diagramas dentro de la nota.
- **Gestos de edición [C]:** tachar para borrar, rayar para eliminar, unir y separar palabras, insertar espacio.
- **Diagramas [C]:** convierte formas dibujadas en diagramas editables.
- **Páginas de dos tipos [C]:** documento con reflujo o "freeform" (canvas libre).
- **Motor propio [C]:** MyScript iink SDK, comercial, con licencia de pago para terceros.

## Qué aprendemos
- **La referencia en matemáticas manuscritas:** escribir, convertir a LaTeX y seguir editando.
- Los gestos de edición con el lápiz evitan cambiar de herramienta.
- Los bloques "inteligentes" dentro del flujo de la nota se parecen a nuestros bloques ` ```ink `, ` ```plot ` y ` ```diagram `.

## Debilidades (oportunidad)
- **[W]** Solo resuelve "cálculos sencillos". No hay CAS completo (integrales, ecuaciones diferenciales, límites, series), ni gráficas paramétricas, ni unidades físicas.
- **[C]** El reconocimiento depende de un SDK cerrado. Euler Notes no puede usarlo sin licencia comercial.

## Lo que Euler Notes **no** hará
No usará ni imitará el SDK iink ni sus gestos patentados. **[Hip]** Puede haber patentes sobre gestos; hay que revisarlo antes de implementar gestos parecidos.

## Fuentes
- [MyScript — Notes versions (Android)](https://help.myscript.com/notes/versions/android/)
- [MyScript — Notes versions (iOS)](https://help.myscript.com/notes/versions/ios/)
- [APKMirror — MyScript Notes 6.3.2 (notas de versión)](https://www.apkmirror.com/apk/myscript/myscript-notes-ai-note-taking/nebo-note-taking-for-students-6-3-2-release/)
