# Cuaderno Científico — Especificación de Producto

> Versión del documento: v0.1 · Estado: borrador aprobado (Fase 0)

## 1. Visión
Cuaderno Científico es un cuaderno digital para escribir ciencia: notas en Markdown, fórmulas LaTeX y cálculo simbólico, todo en el mismo lugar. Funciona en local y sin cuenta. Está pensado primero para Web y Linux, y después para Mobile.

## 2. Usuario objetivo
- **Estudiantes** de matemáticas, física, química e ingeniería que toman apuntes con fórmulas.
- **Docentes** que preparan material con ecuaciones y ejemplos resueltos.

Problema que resuelve: hoy alternan entre un editor de texto, un editor LaTeX y una calculadora simbólica. Cuaderno Científico junta los tres flujos.

## 3. Alcance v0.1

### Casos de uso
| ID | Caso de uso | Descripción |
|---|---|---|
| CU-01 | Gestionar cuadernos | Crear, renombrar, listar y eliminar cuadernos. |
| CU-02 | Gestionar notas | Crear, editar, listar y eliminar notas dentro de un cuaderno. |
| CU-03 | Escribir en Markdown | Editar el texto de la nota con vista previa en vivo. |
| CU-04 | Ver fórmulas LaTeX | `$...$` (en línea) y `$$...$$` (bloque) se muestran como fórmulas en la vista previa. |
| CU-05 | Cálculo simbólico | Introducir una expresión, elegir operación (`simplify`, `diff`, `integrate`, `solve`) y una variable, y obtener el resultado. |
| CU-06 | Insertar resultado | Insertar en la nota el resultado del cálculo en formato LaTeX. |

### Fuera de alcance (v0.1)
- Sincronización en la nube y cuentas de usuario.
- Colaboración en tiempo real.
- Aplicación Mobile (Android/iOS).
- Gráficas de funciones.
- Ejecución de código arbitrario (celdas tipo Jupyter).
- Exportar a PDF.

## 4. Requisitos no funcionales
- **Plataformas:** Flutter Web (Chrome/Firefox) y Linux de escritorio.
- **Local-first:** los datos se guardan en un archivo SQLite local; no hace falta Internet.
- **Seguridad:** el motor de cálculo nunca ejecuta código arbitrario. Las expresiones se interpretan con una lista blanca y un tiempo máximo.
- **Rendimiento:** la vista previa se actualiza en < 200 ms con notas de hasta ~5.000 palabras; `/compute` responde o corta en ≤ 5 s.
- **Idioma:** interfaz en español.

## 5. Criterios de aceptación v0.1
1. Se puede crear un cuaderno, añadirle una nota y que siga ahí al reiniciar app y backend.
2. Escribir `$$\int x^2\,dx$$` en una nota muestra la integral renderizada.
3. Calcular `diff` de `sin(x)*x` respecto a `x` devuelve `x \cos{\left(x \right)} + \sin{\left(x \right)}` y se puede insertar en la nota.
4. Una expresión maliciosa (p. ej. `__import__('os')`) se rechaza con un error claro y sin efectos secundarios.
5. La app funciona igual con `flutter run -d chrome` y con `flutter run -d linux`.

## 6. Métricas de éxito (orientativas)
- Flujo completo (crear nota → fórmula → cálculo → insertar) en menos de 1 minuto para un usuario nuevo.
- Cero cierres inesperados en la prueba manual de aceptación.
