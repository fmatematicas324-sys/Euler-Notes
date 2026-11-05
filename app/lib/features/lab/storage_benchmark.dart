import 'dart:math';
import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../../core/local_db/local_database.dart';
import '../../core/local_db/uuid_v7.dart';

/// Resultado de una medición del laboratorio.
class BenchmarkResult {
  const BenchmarkResult(this.label, this.value, {this.ok, this.detail = ''});

  final String label;
  final String value;

  /// `true`/`false` si hay un criterio de aceptación; `null` si es informativo.
  final bool? ok;
  final String detail;

  @override
  String toString() =>
      '${ok == null ? '·' : (ok! ? '✔' : '✘')} $label: $value'
      '${detail.isEmpty ? '' : ' ($detail)'}';
}

/// Tamaño del banco de pruebas. [standard] imita un curso completo; las
/// pruebas automáticas usan [tiny] para ir rápido.
class BenchmarkSize {
  const BenchmarkSize({
    required this.notebooks,
    required this.pagesPerNotebook,
    required this.autosaves,
    required this.strokes,
    required this.pointsPerStroke,
    required this.liveStrokes,
  });

  final int notebooks;
  final int pagesPerNotebook;
  final int autosaves;
  final int strokes;
  final int pointsPerStroke;
  final int liveStrokes;

  static const standard = BenchmarkSize(
    notebooks: 20,
    pagesPerNotebook: 50,
    autosaves: 200,
    strokes: 300,
    pointsPerStroke: 100,
    liveStrokes: 100,
  );

  static const tiny = BenchmarkSize(
    notebooks: 2,
    pagesPerNotebook: 5,
    autosaves: 5,
    strokes: 10,
    pointsPerStroke: 20,
    liveStrokes: 5,
  );
}

/// Criterios de aceptación del prototipo (`prototipo_almacenamiento.md`).
const maxAutosaveMs = 15.0;
const maxStrokeSaveMs = 15.0;
const maxPageReadMs = 100.0;

/// Ejecuta el banco de pruebas sobre [db] (que debe estar vacía) y la deja
/// vacía al terminar. Llama a [onProgress] antes de cada paso.
Future<List<BenchmarkResult>> runStorageBenchmark(
  LocalDatabase db, {
  BenchmarkSize size = BenchmarkSize.standard,
  void Function(String step)? onProgress,
  Random? random,
}) async {
  final rng = random ?? Random(42);
  final results = <BenchmarkResult>[];
  final watch = Stopwatch();
  double ms() => watch.elapsedMicroseconds / 1000;
  String fmt(double value) => value < 10
      ? value.toStringAsFixed(2)
      : value.toStringAsFixed(0);

  // 1. Motor y configuración.
  onProgress?.call('Abriendo la base de datos');
  watch.start();
  final version = await db.scalar('SELECT sqlite_version()');
  watch.stop();
  results
    ..add(BenchmarkResult('Apertura y primera consulta', '${fmt(ms())} ms'))
    ..add(BenchmarkResult('Versión de SQLite', version));
  final journal = await db.scalar('PRAGMA journal_mode');
  results.add(
    BenchmarkResult(
      'Modo de diario',
      journal,
      ok: journal.toLowerCase() == 'wal',
      detail: 'se espera WAL',
    ),
  );

  // 2. Un curso completo de golpe (como una importación desde el servidor).
  onProgress?.call('Creando cuadernos y páginas');
  final now = DateTime.now().millisecondsSinceEpoch;
  final body = _sampleMarkdown(rng);
  final pageIds = <String>[];
  final notebookIds = <String>[];
  watch
    ..reset()
    ..start();
  await db.transaction(() async {
    for (var n = 0; n < size.notebooks; n++) {
      final notebookId = uuidV7();
      notebookIds.add(notebookId);
      await db
          .into(db.notebooks)
          .insert(
            NotebooksCompanion.insert(
              id: notebookId,
              title: 'Cuaderno $n',
              createdAt: now,
              updatedAt: now,
            ),
          );
      for (var p = 0; p < size.pagesPerNotebook; p++) {
        final pageId = uuidV7();
        pageIds.add(pageId);
        await db
            .into(db.pages)
            .insert(
              PagesCompanion.insert(
                id: pageId,
                notebookId: notebookId,
                title: 'Página $p',
                position: p,
                body: Value(body),
                createdAt: now,
                updatedAt: now,
              ),
            );
      }
    }
  });
  watch.stop();
  results.add(
    BenchmarkResult(
      'Crear ${pageIds.length} páginas (${size.notebooks} cuadernos)',
      '${fmt(ms())} ms',
      detail: '${(body.length / 1024).toStringAsFixed(1)} KB de texto c/u',
    ),
  );

  // 3. Abrir un cuaderno: listar sus páginas.
  onProgress?.call('Leyendo un cuaderno');
  watch
    ..reset()
    ..start();
  final listed =
      await (db.select(db.pages)
            ..where((p) => p.notebookId.equals(notebookIds.first))
            ..orderBy([(p) => OrderingTerm.asc(p.position)]))
          .get();
  watch.stop();
  results.add(
    BenchmarkResult(
      'Abrir un cuaderno (${listed.length} páginas)',
      '${fmt(ms())} ms',
      ok: ms() <= maxPageReadMs,
      detail: 'máx. ${maxPageReadMs.toStringAsFixed(0)} ms',
    ),
  );

  // 4. Autoguardado: cada guardado es su propia transacción, como en el editor.
  onProgress?.call('Simulando el autoguardado');
  final target = pageIds[pageIds.length ~/ 2];
  var worst = 0.0;
  watch.reset();
  for (var i = 0; i < size.autosaves; i++) {
    final single = Stopwatch()..start();
    watch.start();
    await (db.update(db.pages)..where((p) => p.id.equals(target))).write(
      PagesCompanion(
        body: Value('$body\n\nEdición $i'),
        updatedAt: Value(now + i),
      ),
    );
    watch.stop();
    single.stop();
    worst = max(worst, single.elapsedMicroseconds / 1000);
  }
  final autosave = ms() / size.autosaves;
  results.add(
    BenchmarkResult(
      'Autoguardado de una página',
      '${fmt(autosave)} ms de media',
      ok: autosave <= maxAutosaveMs,
      detail: 'peor ${fmt(worst)} ms; máx. ${fmt(maxAutosaveMs)} ms',
    ),
  );

  // 5. Tinta: muchos trazos de golpe y luego uno a uno (al levantar el lápiz).
  onProgress?.call('Guardando tinta');
  final inkPage = pageIds.first;
  StrokesCompanion stroke() {
    final points = _randomStroke(rng, size.pointsPerStroke);
    return StrokesCompanion.insert(
      id: uuidV7(),
      pageId: inkPage,
      tool: 'pen',
      color: 0xFF1C64D9,
      width: 2.5,
      minX: 0,
      minY: 0,
      maxX: 595,
      maxY: 842,
      points: points,
      createdAt: now,
    );
  }

  watch
    ..reset()
    ..start();
  await db.batch((batch) {
    batch.insertAll(db.strokes, [
      for (var i = 0; i < size.strokes; i++) stroke(),
    ]);
  });
  watch.stop();
  final inkBytes = size.strokes * size.pointsPerStroke * 16;
  results.add(
    BenchmarkResult(
      'Guardar ${size.strokes} trazos de golpe',
      '${fmt(ms())} ms',
      detail: '${(inkBytes / 1024).toStringAsFixed(0)} KB de puntos',
    ),
  );

  watch.reset();
  for (var i = 0; i < size.liveStrokes; i++) {
    watch.start();
    await db.into(db.strokes).insert(stroke());
    watch.stop();
  }
  final perStroke = ms() / size.liveStrokes;
  results.add(
    BenchmarkResult(
      'Guardar un trazo al levantar el lápiz',
      '${fmt(perStroke)} ms de media',
      ok: perStroke <= maxStrokeSaveMs,
      detail: 'máx. ${fmt(maxStrokeSaveMs)} ms',
    ),
  );

  watch
    ..reset()
    ..start();
  final strokes = await (db.select(
    db.strokes,
  )..where((s) => s.pageId.equals(inkPage))).get();
  final decoded = strokes.fold<int>(
    0,
    (sum, s) => sum + s.points.lengthInBytes ~/ 16,
  );
  watch.stop();
  results.add(
    BenchmarkResult(
      'Cargar la tinta de una página',
      '${fmt(ms())} ms',
      ok: ms() <= maxPageReadMs,
      detail: '${strokes.length} trazos, $decoded puntos',
    ),
  );

  // 6. Búsqueda de texto completo (FTS5), en una tabla temporal.
  onProgress?.call('Probando la búsqueda (FTS5)');
  try {
    await db.customStatement(
      'CREATE VIRTUAL TABLE temp.lab_search USING fts5(title, body)',
    );
    await db.customStatement(
      'INSERT INTO temp.lab_search SELECT title, body FROM pages',
    );
    watch
      ..reset()
      ..start();
    final hits = await db
        .customSelect(
          "SELECT count(*) AS n FROM temp.lab_search "
          "WHERE lab_search MATCH 'energía'",
        )
        .getSingle();
    watch.stop();
    await db.customStatement('DROP TABLE temp.lab_search');
    results.add(
      BenchmarkResult(
        'Búsqueda de texto (FTS5)',
        '${fmt(ms())} ms',
        ok: true,
        detail: '${hits.data['n']} páginas con «energía»',
      ),
    );
  } on Object catch (error) {
    results.add(
      BenchmarkResult(
        'Búsqueda de texto (FTS5)',
        'no disponible',
        ok: false,
        detail: '$error',
      ),
    );
  }

  // 7. Tamaño y limpieza.
  final pageCount = int.parse(await db.scalar('PRAGMA page_count'));
  final pageSize = int.parse(await db.scalar('PRAGMA page_size'));
  results.add(
    BenchmarkResult(
      'Tamaño de la base de datos',
      '${(pageCount * pageSize / 1024 / 1024).toStringAsFixed(1)} MB',
    ),
  );
  onProgress?.call('Limpiando');
  await db.transaction(() async {
    await db.delete(db.strokes).go();
    await db.delete(db.pages).go();
    await db.delete(db.notebooks).go();
  });
  await db.customStatement('VACUUM');
  return results;
}

/// Puntos `Float32 [x, y, presión, t]` de un trazo con forma de garabato.
Uint8List _randomStroke(Random rng, int points) {
  final data = Float32List(points * 4);
  var x = rng.nextDouble() * 500, y = rng.nextDouble() * 800;
  for (var i = 0; i < points; i++) {
    x += rng.nextDouble() * 4 - 2;
    y += rng.nextDouble() * 4 - 2;
    data
      ..[i * 4] = x
      ..[i * 4 + 1] = y
      ..[i * 4 + 2] = 0.3 + rng.nextDouble() * 0.7
      ..[i * 4 + 3] = i * 8;
  }
  return data.buffer.asUint8List();
}

/// Apunte de ejemplo de unos 2 KB con fórmulas, como una nota real.
String _sampleMarkdown(Random rng) {
  final buffer = StringBuffer('# Trabajo y energía\n\n');
  for (var i = 0; i < 12; i++) {
    buffer
      ..write('El teorema trabajo-energía relaciona el trabajo neto con el ')
      ..write(r'cambio de energía cinética: $W = \Delta K$. ')
      ..write('Ejemplo ${rng.nextInt(100)}: ')
      ..write(r'$K = \tfrac{1}{2} m v^2$.')
      ..write('\n\n');
  }
  return buffer.toString();
}
