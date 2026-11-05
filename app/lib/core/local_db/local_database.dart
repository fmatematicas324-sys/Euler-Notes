import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'local_database.g.dart';

// Base de datos local con Drift (ADR 10). **Prototipo de la Misión 014**: el
// esquema es un subconjunto del de `product_research/arquitectura_tecnica.md`
// §3.1 y sirve para medir; el definitivo se diseñará antes de migrar datos.
//
// Convenciones (ADR 12): identificadores UUID v7 en texto; fechas en
// milisegundos Unix; `deleted_at` para borrados lógicos.
//
// El código `local_database.g.dart` lo genera `build_runner` (en CI:
// `dart run build_runner build`); no se guarda en el repositorio.

@DataClassName('NotebookRow')
class Notebooks extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get cover => text().withDefault(const Constant('classic'))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Página de un cuaderno (sustituirá a la «nota»). En el prototipo el texto
/// Markdown va en `body`; en el modelo final será un objeto de la página.
@DataClassName('PageRow')
class Pages extends Table {
  TextColumn get id => text()();
  TextColumn get notebookId => text().references(Notebooks, #id)();
  TextColumn get title => text()();
  IntColumn get position => integer()();
  TextColumn get size => text().withDefault(const Constant('infinite'))();
  TextColumn get body => text().withDefault(const Constant(''))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Trazo de tinta. `points` empaqueta `Float32 [x, y, presión, t]` por punto
/// (16 B) en coordenadas de página; `min*`/`max*` es la caja envolvente.
@DataClassName('StrokeRow')
class Strokes extends Table {
  TextColumn get id => text()();
  TextColumn get pageId => text().references(Pages, #id)();
  TextColumn get tool => text()();
  IntColumn get color => integer()();
  RealColumn get width => real()();
  RealColumn get minX => real()();
  RealColumn get minY => real()();
  RealColumn get maxX => real()();
  RealColumn get maxY => real()();
  BlobColumn get points => blob()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Notebooks, Pages, Strokes])
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

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await customStatement(
        'CREATE INDEX IF NOT EXISTS pages_by_notebook '
        'ON pages (notebook_id, position)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS strokes_by_page ON strokes (page_id)',
      );
    },
    beforeOpen: (details) async {
      // WAL + synchronous=NORMAL: escrituras rápidas que resisten que Android
      // cierre la app (arquitectura_tecnica.md §3.2).
      await customStatement('PRAGMA journal_mode = WAL');
      await customStatement('PRAGMA synchronous = NORMAL');
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Valor de un `PRAGMA` o consulta de una sola celda, como texto.
  Future<String> scalar(String sql) async {
    final row = await customSelect(sql).getSingle();
    return row.data.values.first.toString();
  }
}
