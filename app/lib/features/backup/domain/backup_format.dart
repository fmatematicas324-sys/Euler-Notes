// Formato de las copias de seguridad de Euler Notes (Misión 017, ADR 24).
//
// Documentación completa: `docs/BACKUP_FORMAT.md`.
//
// Archivo `.eulernotes`: texto UTF-8 en *JSON Lines* (un objeto JSON por
// línea, separadas por `\n`, y `\n` también al final):
//
//   1. Cabecera  {"kind":"header","format":"euler-notes-backup",...}
//   2. Filas     {"kind":"row","table":"notebooks","data":{...}}
//   3. Pie       {"kind":"footer","counts":{...},"rows":N,"sha256":"..."}
//
// El `sha256` del pie es el de todos los bytes anteriores a la línea del pie.
// Un archivo sin pie está incompleto (la exportación se interrumpió).

/// Identificador del formato (campo `format` de la cabecera).
const backupFormatId = 'euler-notes-backup';

/// Versión del formato que escribe esta app. Una restauración futura debe
/// rechazar versiones mayores que la que conoce.
const backupFormatVersion = 1;

/// Extensión recomendada del archivo.
const backupFileExtension = 'eulernotes';

/// Tipo MIME con el que se crea el documento en Android. Genérico a propósito:
/// Android no conoce `.eulernotes` y así no cambia la extensión elegida.
const backupMimeType = 'application/octet-stream';

/// Tablas que se copian, en orden de dependencia: cada tabla solo apunta a
/// las anteriores, así que una restauración puede insertarlas en este orden.
const backupTables = ['notebooks', 'notes', 'drawings'];

/// Relaciones obligatorias: tabla → (columna, tabla a la que apunta).
const backupRelations = {
  'notes': ('notebook_id', 'notebooks'),
  'drawings': ('note_id', 'notes'),
};

/// Versiones del esquema local (`PRAGMA user_version`) que sabe exportar.
const supportedSchemaVersions = {2};

/// Nombre sugerido: `euler-notes-AAAAMMDD-HHMM.eulernotes` (hora local).
String suggestedBackupName(DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'euler-notes-${now.year}${two(now.month)}${two(now.day)}-'
      '${two(now.hour)}${two(now.minute)}.$backupFileExtension';
}

/// Nombre alternativo para el intento [attempt] (2, 3…):
/// `euler-notes-AAAAMMDD-HHMM-2.eulernotes`.
String alternativeBackupName(String suggested, int attempt) {
  final dot = suggested.lastIndexOf('.');
  if (dot <= 0) return '$suggested-$attempt';
  return '${suggested.substring(0, dot)}-$attempt${suggested.substring(dot)}';
}

/// Error de la copia de seguridad. [message] es apto para mostrarse al
/// usuario y nunca incluye contenido de las notas.
class BackupException implements Exception {
  const BackupException(this.code, this.message);

  /// `cancelled`, `write_failed`, `verify_failed`, `unsupported_schema`,
  /// `unknown_table`, `unsupported_platform`, `copy_failed`,
  /// `target_exists` (el destino ya tenía contenido y no se sobrescribió).
  final String code;
  final String message;

  bool get cancelled => code == 'cancelled';

  @override
  String toString() => 'BackupException($code): $message';
}

/// Fases de la exportación, en orden.
enum BackupPhase {
  choosing('Eligiendo dónde guardar'),
  reading('Leyendo la base local'),
  writing('Escribiendo la copia'),
  verifying('Verificando la copia'),
  copying('Guardando en el destino'),
  done('Listo');

  const BackupPhase(this.label);
  final String label;
}

/// Progreso de la exportación. [fraction] es `null` si no se puede estimar.
class BackupProgress {
  const BackupProgress(this.phase, [this.fraction]);

  final BackupPhase phase;
  final double? fraction;
}

typedef BackupProgressCallback = void Function(BackupProgress progress);

/// Permite cancelar una exportación en curso.
class BackupCancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) {
      throw const BackupException('cancelled', 'Copia cancelada');
    }
  }
}

/// Resumen de una copia escrita y verificada.
class BackupSummary {
  const BackupSummary({
    required this.counts,
    required this.schemaVersion,
    required this.bytes,
    required this.sha256,
    required this.createdAt,
    this.warnings = const [],
    this.location,
  });

  /// Filas por tabla (incluye las borradas lógicamente).
  final Map<String, int> counts;
  final int schemaVersion;

  /// Tamaño del archivo y SHA-256 del archivo completo.
  final int bytes;
  final String sha256;
  final DateTime createdAt;

  /// Avisos no fatales (p. ej. un bloque ` ```ink ` sin dibujo).
  final List<String> warnings;

  /// Dónde quedó guardada (ruta o URI), si se conoce.
  final String? location;

  int get rows => counts.values.fold(0, (a, b) => a + b);

  BackupSummary withLocation(String location) => BackupSummary(
    counts: counts,
    schemaVersion: schemaVersion,
    bytes: bytes,
    sha256: sha256,
    createdAt: createdAt,
    warnings: warnings,
    location: location,
  );
}
