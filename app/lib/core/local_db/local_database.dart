import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'local_database.g.dart';

// Base de datos local con Drift (ADR 10, aceptada en la Misión 014).
//
// Esquema de la **Etapa 2** (Misión 015): el mismo modelo que hoy usa la app
// (cuadernos → notas Markdown → dibujos de los bloques ` ```ink `), guardado
// en la tablet. Las páginas con capas (ADR 14) llegarán en la Etapa 3.
//
// Convenciones (ADR 12): identificadores UUID v7 en texto; fechas en
// milisegundos Unix; `deleted_at` para borrados lógicos. `source` (URL del
// servidor) y `source_id` (su id numérico) enlazan cada fila con su origen
// para que la importación se pueda repetir sin duplicar.
//
// El código `local_database.g.dart` lo genera `build_runner` (en CI:
// `dart run build_runner build`); no se guarda en el repositorio.

@DataClassName('NotebookRow')
class Notebooks extends Table {
  TextColumn get id => text()();
  TextColumn get source => text().nullable()();
  IntColumn get sourceId => integer().nullable()();
  TextColumn get title => text()();
  TextColumn get cover => text().withDefault(const Constant('classic'))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Nota Markdown. En el contenido local, los bloques ` ```ink ` apuntan al
/// UUID del dibujo local (`id: <uuid>`), no al id del servidor.
@DataClassName('NoteRow')
class Notes extends Table {
  TextColumn get id => text()();
  TextColumn get source => text().nullable()();
  IntColumn get sourceId => integer().nullable()();
  TextColumn get notebookId => text().references(Notebooks, #id)();
  TextColumn get title => text()();
  TextColumn get content => text().withDefault(const Constant(''))();
  TextColumn get paper => text().withDefault(const Constant('blank'))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Dibujo de un bloque ` ```ink `. Los trazos se guardan como el JSON que ya
/// usa la app (`Stroke.toJson`), para no perder nada; el formato compacto
/// `Float32` medido en la Misión 014 queda para la Etapa 3.
@DataClassName('DrawingRow')
class Drawings extends Table {
  TextColumn get id => text()();
  TextColumn get source => text().nullable()();
  IntColumn get sourceId => integer().nullable()();
  TextColumn get noteId => text().references(Notes, #id)();
  RealColumn get width => real()();
  RealColumn get height => real()();
  TextColumn get strokes => text().withDefault(const Constant('[]'))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Notebooks, Notes, Drawings])
class LocalDatabase extends _$LocalDatabase {
  LocalDatabase(super.executor);

  /// Base de datos en un archivo de la app ([name]`.sqlite`), en un isolate
  /// aparte para no bloquear la interfaz.
  factory LocalDatabase.open(String name) => LocalDatabase(
    driftDatabase(
      name: name,
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      ),
    ),
  );

  /// 1: prototipo de la Misión 014 (solo en la base del laboratorio).
  /// 2: esquema de la Etapa 2 (Misión 015).
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createIndexes();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // La versión 1 solo existió en la base del laboratorio (datos de
        // prueba que se vacían): se rehace entera.
        for (final table in ['strokes', 'pages', 'notebooks']) {
          await customStatement('DROP TABLE IF EXISTS $table');
        }
        await m.createAll();
        await _createIndexes();
      }
    },
    beforeOpen: (details) async {
      // WAL + synchronous=NORMAL: escrituras rápidas que resisten que Android
      // cierre la app (arquitectura_tecnica.md §3.2).
      await customStatement('PRAGMA journal_mode = WAL');
      await customStatement('PRAGMA synchronous = NORMAL');
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> _createIndexes() async {
    const statements = [
      'CREATE INDEX IF NOT EXISTS notes_by_notebook ON notes (notebook_id)',
      'CREATE INDEX IF NOT EXISTS drawings_by_note ON drawings (note_id)',
      // Una fila por origen: la importación se puede repetir sin duplicar.
      'CREATE UNIQUE INDEX IF NOT EXISTS notebooks_by_source '
          'ON notebooks (source, source_id)',
      'CREATE UNIQUE INDEX IF NOT EXISTS notes_by_source '
          'ON notes (source, source_id)',
      'CREATE UNIQUE INDEX IF NOT EXISTS drawings_by_source '
          'ON drawings (source, source_id)',
    ];
    for (final sql in statements) {
      await customStatement(sql);
    }
  }

  /// Valor de un `PRAGMA` o consulta de una sola celda, como texto.
  Future<String> scalar(String sql) async {
    final row = await customSelect(sql).getSingle();
    return row.data.values.first.toString();
  }
}
