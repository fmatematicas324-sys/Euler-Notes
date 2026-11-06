import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/api_client.dart';
import '../../core/api_exception.dart';
import '../../core/local_db/local_database.dart';
import '../../core/local_db/uuid_v7.dart';

/// Resultado de una importación desde el servidor.
class ImportReport {
  ImportReport({required this.source});

  final String source;
  int notebooks = 0;
  int notes = 0;
  int drawings = 0;
  int created = 0;
  int updated = 0;

  /// Filas que no se tocaron porque la tablet tiene una versión más reciente
  /// (editadas o borradas en el modo sin conexión).
  int kept = 0;

  /// Avisos no fatales (p. ej. un bloque ` ```ink ` que apunta a un dibujo
  /// que ya no existe en el servidor).
  final warnings = <String>[];

  /// Diferencias encontradas al releer la copia local. Vacío = todo bien.
  final mismatches = <String>[];

  Duration elapsed = Duration.zero;

  bool get verified => mismatches.isEmpty;
}

/// Bloque ` ```ink ` (misma apertura que reconoce la vista previa).
final _inkStart = RegExp(r'^\s*```\s*ink\s*$');
final _blockEnd = RegExp(r'^\s*```\s*$');
final _inkId = RegExp(r'^(\s*id\s*:\s*)(\d+)(\s*)$');

/// Ids numéricos de dibujo que aparecen en los bloques ` ```ink ` de [markdown].
List<int> inkDrawingIds(String markdown) {
  final ids = <int>[];
  var inside = false;
  for (final line in const LineSplitter().convert(markdown)) {
    if (!inside) {
      inside = _inkStart.hasMatch(line);
    } else if (_blockEnd.hasMatch(line)) {
      inside = false;
    } else if (_inkId.firstMatch(line) case final match?) {
      ids.add(int.parse(match[2]!));
    }
  }
  return ids;
}

/// Cambia, solo dentro de los bloques ` ```ink `, el id del servidor por el
/// UUID local según [map]. Los ids sin correspondencia se dejan como están.
/// Conserva los saltos de línea originales.
String rewriteInkIds(String markdown, Map<int, String> map) {
  final out = StringBuffer();
  var inside = false;
  final lines = markdown.split('\n');
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    if (!inside) {
      inside = _inkStart.hasMatch(line);
    } else if (_blockEnd.hasMatch(line)) {
      inside = false;
    } else if (_inkId.firstMatch(line) case final match?) {
      final local = map[int.parse(match[2]!)];
      if (local != null) line = '${match[1]}$local${match[3]}';
    }
    out.write(line);
    if (i < lines.length - 1) out.write('\n');
  }
  return out.toString();
}

/// Copia los cuadernos, notas y dibujos del servidor a la base local.
///
/// - **No modifica el servidor** (solo hace `GET`).
/// - Se puede repetir: cada fila local recuerda su origen (`source`,
///   `source_id`) y se actualiza en lugar de duplicarse.
/// - Todo ocurre en una transacción: si algo falla, la copia local queda como
///   estaba.
/// - Al terminar, relee la copia local y la compara con lo descargado.
class ServerImporter {
  ServerImporter(this._api, this._db, this._source);

  final ApiClient _api;
  final LocalDatabase _db;
  final String _source;

  Future<ImportReport> run({void Function(String step)? onProgress}) async {
    final watch = Stopwatch()..start();
    final report = ImportReport(source: _source);

    // 1. Descargar todo antes de escribir nada.
    onProgress?.call('Leyendo los cuadernos');
    final notebooks = await _list('/notebooks');
    final notes = <Map<String, dynamic>>[];
    for (final notebook in notebooks) {
      onProgress?.call('Leyendo «${notebook['title']}»');
      for (final summary in await _list('/notebooks/${notebook['id']}/notes')) {
        notes.add(await _object('/notes/${summary['id']}'));
      }
    }
    final drawings = <int, Map<String, dynamic>>{};
    for (final note in notes) {
      for (final id in inkDrawingIds(note['content'] as String)) {
        if (drawings.containsKey(id)) continue;
        onProgress?.call('Leyendo el dibujo $id');
        try {
          drawings[id] = await _object('/drawings/$id');
        } on ApiException catch (error) {
          if (error.statusCode != 404) rethrow;
          report.warnings.add(
            'La nota «${note['title']}» usa el dibujo $id, que no existe en '
            'el servidor; se deja la referencia como está.',
          );
        }
      }
    }

    // 2. Escribir en una sola transacción.
    onProgress?.call('Guardando en la tablet');
    final expected = <String, Map<String, Object?>>{}; // id local → datos
    await _db.transaction(() async {
      final notebookIds = <int, String>{};
      for (final notebook in notebooks) {
        final id = await _upsertNotebook(notebook, report);
        notebookIds[notebook['id'] as int] = id;
        report.notebooks++;
      }

      final noteIds = <int, String>{};
      final written = <int>{}; // notas que sí se escribieron
      for (final note in notes) {
        final notebookId = notebookIds[note['notebook_id'] as int];
        if (notebookId == null) continue; // la nota cambió de cuaderno
        final (id, wrote) = await _upsertNote(
          note,
          notebookId,
          content: note['content'] as String, // provisional
          report: report,
        );
        noteIds[note['id'] as int] = id;
        if (wrote) written.add(note['id'] as int);
        report.notes++;
      }

      final drawingIds = <int, String>{};
      for (final MapEntry(key: serverId, value: drawing) in drawings.entries) {
        final noteId = noteIds[drawing['note_id'] as int];
        if (noteId == null) {
          report.warnings.add(
            'El dibujo $serverId pertenece a una nota que no se importó.',
          );
          continue;
        }
        drawingIds[serverId] = await _upsertDrawing(drawing, noteId, report);
        report.drawings++;
      }

      // Con todos los UUID ya conocidos, se reescriben los bloques ```ink.
      for (final note in notes) {
        final localId = noteIds[note['id'] as int];
        if (localId == null || !written.contains(note['id'])) continue;
        final content = rewriteInkIds(note['content'] as String, drawingIds);
        await (_db.update(_db.notes)..where((n) => n.id.equals(localId)))
            .write(NotesCompanion(content: Value(content)));
        expected[localId] = {'title': note['title'], 'content': content};
      }
    });

    // 3. Verificar releyendo lo escrito.
    onProgress?.call('Verificando');
    await _verify(report, expected);
    watch.stop();
    report.elapsed = watch.elapsed;
    return report;
  }

  Future<List<Map<String, dynamic>>> _list(String path) async =>
      (await _api.get(path) as List<dynamic>).cast<Map<String, dynamic>>();

  Future<Map<String, dynamic>> _object(String path) async =>
      await _api.get(path) as Map<String, dynamic>;

  static int _millis(Object? iso) =>
      iso is String
          ? DateTime.parse(iso).millisecondsSinceEpoch
          : DateTime.now().millisecondsSinceEpoch;

  static void _count(ImportReport report, {required bool isNew}) {
    if (isNew) {
      report.created++;
    } else {
      report.updated++;
    }
  }

  /// Id local y fecha de la última modificación de la fila importada antes
  /// desde [sourceId], o `null` si es nueva.
  Future<(String, int)?> _existing(TableInfo table, int sourceId) async {
    final row = await _db
        .customSelect(
          'SELECT id, updated_at FROM ${table.actualTableName} '
          'WHERE source = ? AND source_id = ?',
          variables: [Variable.withString(_source), Variable.withInt(sourceId)],
          readsFrom: {table},
        )
        .getSingleOrNull();
    return row == null
        ? null
        : (row.read<String>('id'), row.read<int>('updated_at'));
  }

  /// La tablet gana si su versión es más reciente que la del servidor: no se
  /// pierde lo escrito (o borrado) en el modo sin conexión.
  bool _keepLocal((String, int)? existing, Map<String, dynamic> json) =>
      existing != null && existing.$2 > _millis(json['updated_at']);

  Future<String> _upsertNotebook(
    Map<String, dynamic> json,
    ImportReport report,
  ) async {
    final sourceId = json['id'] as int;
    final existing = await _existing(_db.notebooks, sourceId);
    if (_keepLocal(existing, json)) {
      report.kept++;
      return existing!.$1;
    }
    final row = NotebooksCompanion(
      id: Value(existing?.$1 ?? uuidV7()),
      source: Value(_source),
      sourceId: Value(sourceId),
      title: Value(json['title'] as String),
      cover: Value(json['cover'] as String? ?? 'classic'),
      createdAt: Value(_millis(json['created_at'])),
      updatedAt: Value(_millis(json['updated_at'])),
      deletedAt: const Value(null),
    );
    await _db.into(_db.notebooks).insertOnConflictUpdate(row);
    _count(report, isNew: existing == null);
    return row.id.value;
  }

  /// Devuelve el id local y si se escribió (`false` = se conservó la versión
  /// de la tablet).
  Future<(String, bool)> _upsertNote(
    Map<String, dynamic> json,
    String notebookId, {
    required String content,
    required ImportReport report,
  }) async {
    final sourceId = json['id'] as int;
    final existing = await _existing(_db.notes, sourceId);
    if (_keepLocal(existing, json)) {
      report.kept++;
      return (existing!.$1, false);
    }
    final row = NotesCompanion(
      id: Value(existing?.$1 ?? uuidV7()),
      source: Value(_source),
      sourceId: Value(sourceId),
      notebookId: Value(notebookId),
      title: Value(json['title'] as String),
      content: Value(content),
      paper: Value(json['paper'] as String? ?? 'blank'),
      createdAt: Value(_millis(json['created_at'])),
      updatedAt: Value(_millis(json['updated_at'])),
      deletedAt: const Value(null),
    );
    await _db.into(_db.notes).insertOnConflictUpdate(row);
    _count(report, isNew: existing == null);
    return (row.id.value, true);
  }

  Future<String> _upsertDrawing(
    Map<String, dynamic> json,
    String noteId,
    ImportReport report,
  ) async {
    final sourceId = json['id'] as int;
    final existing = await _existing(_db.drawings, sourceId);
    if (_keepLocal(existing, json)) {
      report.kept++;
      return existing!.$1;
    }
    final row = DrawingsCompanion(
      id: Value(existing?.$1 ?? uuidV7()),
      source: Value(_source),
      sourceId: Value(sourceId),
      noteId: Value(noteId),
      width: Value((json['width'] as num).toDouble()),
      height: Value((json['height'] as num).toDouble()),
      strokes: Value(jsonEncode(json['strokes'] ?? const [])),
      createdAt: Value(_millis(json['created_at'])),
      updatedAt: Value(_millis(json['updated_at'])),
    );
    await _db.into(_db.drawings).insertOnConflictUpdate(row);
    _count(report, isNew: existing == null);
    return row.id.value;
  }

  Future<void> _verify(
    ImportReport report,
    Map<String, Map<String, Object?>> expected,
  ) async {
    Future<int> count(String table) async {
      final row = await _db
          .customSelect(
            'SELECT count(*) AS n FROM $table WHERE source = ?',
            variables: [Variable.withString(_source)],
          )
          .getSingle();
      return row.read<int>('n');
    }
    final notebooks = await count('notebooks');
    if (notebooks < report.notebooks) {
      report.mismatches.add(
        'Cuadernos: ${report.notebooks} en el servidor, $notebooks en la tablet',
      );
    }
    final notes = await count('notes');
    if (notes < report.notes) {
      report.mismatches.add(
        'Notas: ${report.notes} en el servidor, $notes en la tablet',
      );
    }
    final drawings = await count('drawings');
    if (drawings < report.drawings) {
      report.mismatches.add(
        'Dibujos: ${report.drawings} importados, $drawings en la tablet',
      );
    }
    for (final MapEntry(key: id, value: data) in expected.entries) {
      final row = await (_db.select(
        _db.notes,
      )..where((n) => n.id.equals(id))).getSingleOrNull();
      if (row == null ||
          row.title != data['title'] ||
          row.content != data['content']) {
        report.mismatches.add('La nota «${data['title']}» no coincide');
      }
    }
  }
}
