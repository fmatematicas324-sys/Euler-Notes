# Formato de las copias de seguridad (`.eulernotes`, versión 1)

Misión 017 · ADR 24. Código: `app/lib/features/backup/`.

Una copia contiene **toda la base local de la tablet** (`euler_notes.sqlite`):
cuadernos, notas y dibujos, incluidas las filas borradas lógicamente
(`deleted_at`), con sus identificadores y relaciones intactos. No contiene la
dirección del servidor, el token de acceso ni ninguna otra preferencia, ni los
borradores de notas del servidor (Misión 013), que viven fuera de la base.

## 1. Estructura

Texto **UTF-8** en *JSON Lines*: un objeto JSON por línea, separadas por `\n`,
y un `\n` final. Los saltos de línea dentro de las notas van escapados (`\n`)
dentro de su línea JSON. Tres tipos de línea, en este orden:

### 1.1 Cabecera (primera línea)

```json
{"kind":"header","format":"euler-notes-backup","formatVersion":1,
 "createdAt":"2026-11-06T15:30:00.000Z","app":"Euler Notes","appVersion":"0.4.0+4",
 "schemaVersion":2,
 "tables":{"notebooks":{"columns":["id","source","source_id","title","cover","created_at","updated_at","deleted_at"]},
           "notes":{"columns":[...]},"drawings":{"columns":[...]}}}
```

| Campo | Significado |
|---|---|
| `format` | Siempre `euler-notes-backup`. |
| `formatVersion` | Versión de **este formato**. Una app que no la conozca debe rechazar el archivo. |
| `createdAt` | Momento de la copia, ISO 8601 en UTC. |
| `appVersion` | Versión de la app que la generó (`pubspec.yaml`). |
| `schemaVersion` | Versión del **esquema de la base local** (`PRAGMA user_version`) del que salieron las filas. |
| `tables.<t>.columns` | Columnas de cada tabla tal como estaban en la base. |

### 1.2 Filas

```json
{"kind":"row","table":"notes","data":{"id":"01a1ae16-…","source":null,"source_id":null,
 "notebook_id":"01a1ae10-…","title":"Energía","content":"$W = \\Delta K$\n\n```ink\nid: 01a1ae17-…\n```",
 "paper":"grid","created_at":1762400000000,"updated_at":1762400100000,"deleted_at":null}}
```

- `data` es la fila **tal cual** está en SQLite, con los nombres de columna
  de SQL: texto, enteros (fechas en milisegundos Unix), reales y `null`.
  Si en el futuro hubiera columnas binarias, irían como `{"base64":"…"}`.
- Orden de las tablas: `notebooks` → `notes` → `drawings` (cada tabla solo
  apunta a las anteriores; una restauración puede insertarlas en este orden).
  Dentro de cada tabla, por `id`.
- Los ids son UUID v7 (ADR 12). Los dibujos guardan los trazos en el JSON de
  `Stroke.toJson` (columna `strokes`), sin cambios.
- Única transformación: a la columna `source` (URL del servidor de origen) se
  le quitan usuario, contraseña, consulta y fragmento si los tuviera, para
  que ninguna credencial acabe en la copia. Normalmente no tiene nada de eso
  y se copia igual.

### 1.3 Pie (última línea)

```json
{"kind":"footer","counts":{"notebooks":3,"notes":12,"drawings":7},"rows":22,
 "sha256":"<64 hex>"}
```

`sha256` es el SHA-256 de **todos los bytes anteriores a la línea del pie**
(cabecera y filas, con sus `\n`).

## 2. Cómo se garantiza la integridad

Al exportar:

1. Se leen todas las tablas **en una sola transacción de lectura**: la copia es
   una foto coherente aunque la app guarde algo a la vez. Exportar **no
   escribe nada** en la base (las pruebas lo comprueban con `total_changes()`).
2. Se rechaza la exportación si el esquema no es uno conocido (hoy, el 2) o si
   hay una tabla desconocida con datos: así nada se pierde en silencio.
3. Se escribe en `<nombre>.partial`, se vuelca al disco (`fsync`) y se
   **relee entero** con el verificador (§3). Solo si todo cuadra se renombra al
   nombre final. Si algo falla o se cancela, el `.partial` se borra.
4. En Android, el archivo verificado se copia al documento que eligió el
   usuario (selector del sistema, sin permisos de almacenamiento); el
   documento se **relee** y su SHA-256 y tamaño deben coincidir. Si no, o si
   algo falla después de elegir el destino, **el documento se borra**.
   La comparación usa el SHA-256 **completo** (64 cifras hex). Si el proveedor
   no acepta el modo `"wt"` se usa `"w"`, y si entrega una tubería sin
   `fsync` (proveedores en la nube) se sigue adelante: la relectura decide.
   Mientras Android copia al destino, la operación ya no se puede cancelar.

El verificador (`verifyBackupFile`) comprueba:

- el archivo no está vacío y termina en `\n`;
- la primera línea es una cabecera `euler-notes-backup` con una
  `formatVersion` conocida;
- la última línea es el pie (si falta, el archivo está incompleto);
- el SHA-256 del pie coincide con el de los bytes anteriores;
- los conteos del pie coinciden con las filas leídas;
- cada fila tiene `id`, sin duplicados por tabla;
- cada nota apunta a un cuaderno de la copia y cada dibujo a una nota de la
  copia.

Avisos (no impiden la copia): ids que no tienen forma de UUID y bloques
` ```ink ` que apuntan a un dibujo que no existe (ya faltaba en la base).

Para comprobar a mano el SHA-256 de un archivo completo (lo muestra la app,
abreviado):

```sh
sha256sum euler-notes-20261106-1530.eulernotes
```

## 3. Compatibilidad futura

- **Restaurar** (próxima misión) debe: verificar el archivo con las mismas
  reglas; rechazar `formatVersion` mayores que la suya; aceptar
  `schemaVersion` menores y migrarlas (rellenando columnas nuevas con sus
  valores por defecto); y no duplicar filas cuyo `id` ya existe.
- Cambios **compatibles** (columna nueva con valor por defecto, tabla nueva al
  final del orden) mantienen `formatVersion = 1` y suben `schemaVersion`.
- Cambios **incompatibles** (cambiar el significado de un campo, dividir el
  archivo, comprimirlo, cifrarlo) suben `formatVersion`.
- Adjuntos (PDF, imágenes) aún no existen en la base local; cuando existan,
  probablemente obliguen a un contenedor (ZIP) y a `formatVersion = 2`.
