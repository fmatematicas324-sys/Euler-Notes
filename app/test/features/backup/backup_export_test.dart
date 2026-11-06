import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:euler_notes/core/local_db/local_database.dart';
import 'package:euler_notes/features/backup/data/backup_exporter.dart';
import 'package:euler_notes/features/backup/data/backup_verifier.dart';
import 'package:euler_notes/features/backup/domain/backup_format.dart';
import 'package:euler_notes/features/ink/data/local_drawings_repository.dart';
import 'package:euler_notes/features/ink/domain/stroke.dart';
import 'package:euler_notes/features/notebooks/data/local_notebooks_repository.dart';
import 'package:euler_notes/features/notes/data/local_notes_repository.dart';
import 'package:flutter_test/flutter_test.dart';

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

/// Contenido completo de la base: para comprobar que exportar no la cambia.
Future<String> dump(LocalDatabase db) async {
  final out = StringBuffer();
  for (final table in backupTables) {
    final rows = await db
        .customSelect('SELECT * FROM "$table" ORDER BY id')
        .get();
    out.writeln(jsonEncode([for (final r in rows) r.data]));
  }
  out.write(await db.scalar('PRAGMA user_version'));
  return out.toString();
}

/// Filas de un archivo de copia, por tabla.
Map<String, List<Map<String, dynamic>>> rowsOf(File file) {
  final rows = {for (final t in backupTables) t: <Map<String, dynamic>>[]};
  for (final line in file.readAsLinesSync()) {
    final json = jsonDecode(line) as Map<String, dynamic>;
    if (json['kind'] == 'row') {
      rows[json['table']]!.add(json['data'] as Map<String, dynamic>);
    }
  }
  return rows;
}

/// Escribe un archivo con [lines] y un pie correcto (para probar el
/// verificador con contenidos manipulados pero bien sellados).
void writeSealed(File file, List<Map<String, Object?>> lines) {
  final body = StringBuffer();
  final counts = {for (final t in backupTables) t: 0};
  for (final line in lines) {
    body.write('${jsonEncode(line)}\n');
    if (line['kind'] == 'row') {
      counts[line['table']! as String] = counts[line['table']]! + 1;
    }
  }
  final text = body.toString();
  final footer = {
    'kind': 'footer',
    'counts': counts,
    'rows': counts.values.fold(0, (a, b) => a + b),
    'sha256': sha256.convert(utf8.encode(text)).toString(),
  };
  file.writeAsStringSync('$text${jsonEncode(footer)}\n');
}

Map<String, Object?> header() => {
  'kind': 'header',
  'format': backupFormatId,
  'formatVersion': 1,
  'createdAt': '2026-11-06T10:00:00.000Z',
  'schemaVersion': 2,
};

Map<String, Object?> row(String table, Map<String, Object?> data) => {
  'kind': 'row',
  'table': table,
  'data': data,
};

/// Escritor que falla después de [okWrites] escrituras.
class FailingWriter implements BackupWriter {
  FailingWriter(this._inner, this.okWrites);

  final BackupWriter _inner;
  final int okWrites;
  int writes = 0;
  bool aborted = false;

  @override
  Future<void> write(List<int> bytes) async {
    if (++writes > okWrites) {
      throw const FileSystemException('No space left on device');
    }
    await _inner.write(bytes);
  }

  @override
  Future<void> close() => _inner.close();

  @override
  Future<void> abort() async {
    aborted = true;
    await _inner.abort();
  }
}

void main() {
  late Directory dir;
  late LocalDatabase db;
  late File target;

  BackupExporter exporter({BackupWriterFactory? openWriter}) => BackupExporter(
    db,
    appVersion: '0.4.0+4',
    clock: () => DateTime.utc(2026, 11, 6, 10),
    openWriter: openWriter,
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('euler-backup-test-');
    target = File('${dir.path}/copia.eulernotes');
    db = LocalDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  /// Solo deben quedar en la carpeta los archivos esperados (nada `.partial`).
  List<String> files() =>
      dir.listSync().map((e) => e.uri.pathSegments.last).toList()..sort();

  group('exportación', () {
    test('base vacía: cabecera y pie, sin filas, verificable', () async {
      final progress = <BackupPhase>[];
      final summary = await exporter().exportTo(
        target,
        onProgress: (p) => progress.add(p.phase),
      );
      expect(summary.counts, {'notebooks': 0, 'notes': 0, 'drawings': 0});
      expect(summary.schemaVersion, 2);
      expect(files(), ['copia.eulernotes']);

      final lines = target.readAsLinesSync();
      expect(lines, hasLength(2));
      final head = jsonDecode(lines.first) as Map<String, dynamic>;
      expect(head['format'], backupFormatId);
      expect(head['formatVersion'], backupFormatVersion);
      expect(head['schemaVersion'], 2);
      expect(head['appVersion'], '0.4.0+4');
      expect(head['createdAt'], '2026-11-06T10:00:00.000Z');
      expect((head['tables'] as Map)['notes']['columns'], contains('content'));

      final check = await verifyBackupFile(target);
      expect(check.sha256, summary.sha256);
      expect(check.bytes, target.lengthSync());
      expect(
        progress,
        containsAllInOrder([
          BackupPhase.reading,
          BackupPhase.writing,
          BackupPhase.verifying,
          BackupPhase.done,
        ]),
      );
    });

    test('varios cuadernos con sus notas y relaciones', () async {
      final notebooks = LocalNotebooksRepository(db);
      final notes = LocalNotesRepository(db);
      final ids = <String, List<String>>{};
      for (final title in ['Física', 'Cálculo', 'Álgebra lineal']) {
        final notebook = await notebooks.create(title);
        ids[notebook.id] = [
          for (var i = 0; i < 3; i++)
            (await notes.create(notebook.id, '$title $i')).id,
        ];
      }

      final summary = await exporter().exportTo(target);
      expect(summary.counts, {'notebooks': 3, 'notes': 9, 'drawings': 0});

      final rows = rowsOf(target);
      expect(rows['notebooks']!.map((r) => r['id']).toSet(), ids.keys.toSet());
      for (final note in rows['notes']!) {
        expect(ids[note['notebook_id']], contains(note['id']));
      }
      // Los cuadernos van antes que sus notas (orden de restauración).
      final kinds = [
        for (final l in target.readAsLinesSync())
          (jsonDecode(l) as Map)['table'],
      ].whereType<String>().toList();
      expect(kinds.lastIndexOf('notebooks'), lessThan(kinds.indexOf('notes')));
    });

    test('notas con LaTeX se copian byte a byte', () async {
      final notebook = await LocalNotebooksRepository(db).create('Física');
      final notes = LocalNotesRepository(db);
      final note = await notes.create(notebook.id, r'Ecuaciones \LaTeX');
      const latex =
          r'# Maxwell'
          '\n\n'
          r'$$\nabla \cdot \mathbf{E} = \frac{\rho}{\varepsilon_0}$$'
          '\n'
          r'En línea: $\int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}$, '
          r'"comillas", tab:	y emoji ∑ ∂ ℏ 🙂'
          '\r\n'
          r'\begin{pmatrix} a & b \\ c & d \end{pmatrix}';
      await notes.update(note.id, content: latex);

      await exporter().exportTo(target);
      final exported = rowsOf(target)['notes']!.single;
      expect(exported['content'], latex);
      expect(exported['title'], r'Ecuaciones \LaTeX');
      // Una nota por línea: los saltos de línea quedan escapados.
      expect(target.readAsLinesSync(), hasLength(4));
    });

    test('dibujos y bloques de tinta', () async {
      final notebook = await LocalNotebooksRepository(db).create('Física');
      final notes = LocalNotesRepository(db);
      final note = await notes.create(notebook.id, 'Tinta');
      final drawings = LocalDrawingsRepository(db);
      final drawing = await drawings.create(note.id);
      final stroke = Stroke.fromJson(const {
        'tool': 'pen',
        'color': '#1c64d9',
        'width': 2.5,
        'points': [1.0, 2.0, 0.5, 3.25, 4.0, 0.6],
      });
      await drawings.saveStrokes(drawing.id, [stroke]);
      await notes.update(
        note.id,
        content: 'Antes\n\n```ink\nid: ${drawing.id}\n```\n\nDespués',
      );

      final summary = await exporter().exportTo(target);
      expect(summary.counts['drawings'], 1);
      expect(summary.warnings, isEmpty);

      final exported = rowsOf(target)['drawings']!.single;
      final stored = (await db.select(db.drawings).get()).single;
      expect(exported['id'], drawing.id);
      expect(exported['note_id'], note.id);
      expect(exported['width'], 1000.0);
      expect(exported['height'], 700.0);
      expect(exported['strokes'], stored.strokes); // el JSON, sin tocar
      final strokes = jsonDecode(exported['strokes'] as String) as List;
      expect(
        Stroke.fromJson(strokes.single as Map<String, dynamic>).toJson(),
        stroke.toJson(),
      );
      expect(inkReferences(rowsOf(target)['notes']!.single['content']), [
        drawing.id,
      ]);
    });

    test('un bloque de tinta sin dibujo es un aviso, no un error', () async {
      final notebook = await LocalNotebooksRepository(db).create('Física');
      final notes = LocalNotesRepository(db);
      final note = await notes.create(notebook.id, 'Tinta');
      await notes.update(note.id, content: '```ink\nid: no-existe\n```');
      final summary = await exporter().exportTo(target);
      expect(summary.warnings, hasLength(1));
      expect(summary.warnings.single, isNot(contains('no-existe')));
    });

    test('conserva los UUID y las filas borradas lógicamente', () async {
      final notebooks = LocalNotebooksRepository(db);
      final notes = LocalNotesRepository(db);
      final kept = await notebooks.create('Física');
      final gone = await notebooks.create('Borrado');
      final note = await notes.create(kept.id, 'Energía');
      await notes.delete(note.id);
      await notebooks.delete(gone.id);

      await exporter().exportTo(target);
      final rows = rowsOf(target);
      final all = [for (final t in backupTables) ...rows[t]!];
      expect(all, hasLength(3));
      for (final r in all) {
        expect(r['id'], matches(_uuid));
      }
      final stored = (await db.select(db.notebooks).get()).map((n) => n.id);
      expect(rows['notebooks']!.map((r) => r['id']), unorderedEquals(stored));
      // Los borrados conservan `deleted_at` para que una restauración futura
      // (y la importación) los siga respetando.
      expect(rows['notes']!.single['deleted_at'], isNotNull);
      expect(
        rows['notebooks']!.firstWhere((r) => r['id'] == gone.id)['deleted_at'],
        isNotNull,
      );
    });

    test('no modifica la base de datos', () async {
      final notebook = await LocalNotebooksRepository(db).create('Física');
      final note = await LocalNotesRepository(db).create(notebook.id, 'Nota');
      await LocalDrawingsRepository(db).create(note.id);
      final before = await dump(db);
      final changes = await db.scalar('SELECT total_changes()');

      await exporter().exportTo(target);
      await exporter().exportTo(File('${dir.path}/otra.eulernotes'));

      expect(await dump(db), before);
      expect(await db.scalar('SELECT total_changes()'), changes);
    });

    test('no incluye credenciales en la URL de origen', () async {
      final now = DateTime(2026).millisecondsSinceEpoch;
      await db
          .into(db.notebooks)
          .insert(
            NotebooksCompanion.insert(
              id: '0190f5c2-0000-7000-8000-000000000001',
              source: const Value('http://ana:secreto@192.168.1.5:8000?t=x1'),
              sourceId: const Value(4),
              title: 'Importado',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await exporter().exportTo(target);
      final text = target.readAsStringSync();
      expect(text, isNot(contains('secreto')));
      expect(text, isNot(contains('x1')));
      expect(
        rowsOf(target)['notebooks']!.single['source'],
        'http://192.168.1.5:8000',
      );
      // La base no cambia.
      expect(
        (await db.select(db.notebooks).get()).single.source,
        'http://ana:secreto@192.168.1.5:8000?t=x1',
      );
    });

    test('una URL de origen normal se copia igual', () {
      expect(sanitizeSourceUrl('http://pc:8000'), 'http://pc:8000');
      expect(sanitizeSourceUrl('https://u:p@pc/api?a=1#x'), 'https://pc/api');
    });
  });

  group('interrupciones y errores de escritura', () {
    Future<void> seed() async {
      final notebook = await LocalNotebooksRepository(db).create('Física');
      for (var i = 0; i < 120; i++) {
        await LocalNotesRepository(db).create(notebook.id, 'Nota $i');
      }
    }

    test('si falla la escritura no queda ningún archivo', () async {
      await seed();
      final before = await dump(db);
      late FailingWriter writer;
      final future = exporter(
        openWriter: (file) async =>
            writer = FailingWriter(await FileBackupWriter.open(file), 10),
      ).exportTo(target);
      await expectLater(
        future,
        throwsA(
          isA<BackupException>().having((e) => e.code, 'code', 'write_failed'),
        ),
      );
      expect(writer.aborted, isTrue);
      expect(files(), isEmpty);
      expect(await dump(db), before);
    });

    test(
      'un error no estropea una copia anterior con el mismo nombre',
      () async {
        await seed();
        await exporter().exportTo(target);
        final previous = target.readAsBytesSync();

        await expectLater(
          exporter(
            openWriter: (file) async =>
                FailingWriter(await FileBackupWriter.open(file), 3),
          ).exportTo(target),
          throwsA(isA<BackupException>()),
        );
        expect(target.readAsBytesSync(), previous);
        expect(files(), ['copia.eulernotes']);
      },
    );

    test('cancelar a mitad no deja archivos', () async {
      await seed();
      final cancel = BackupCancelToken();
      await expectLater(
        exporter().exportTo(
          target,
          cancel: cancel,
          onProgress: (p) {
            if (p.phase == BackupPhase.writing && (p.fraction ?? 0) > 0.3) {
              cancel.cancel();
            }
          },
        ),
        throwsA(isA<BackupException>().having((e) => e.cancelled, 'c', true)),
      );
      expect(files(), isEmpty);
    });

    test('carpeta de destino inexistente', () async {
      await expectLater(
        exporter().exportTo(File('${dir.path}/no/existe/copia.eulernotes')),
        throwsA(
          isA<BackupException>().having((e) => e.code, 'code', 'write_failed'),
        ),
      );
    });

    test('un .partial viejo se reemplaza', () async {
      File('${target.path}.partial').writeAsStringSync('basura');
      await exporter().exportTo(target);
      expect(files(), ['copia.eulernotes']);
      await verifyBackupFile(target);
    });
  });

  group('verificación de integridad', () {
    Future<void> exportSome() async {
      final notebook = await LocalNotebooksRepository(db).create('Física');
      final note = await LocalNotesRepository(db).create(notebook.id, 'Nota');
      await LocalDrawingsRepository(db).create(note.id);
      await exporter().exportTo(target);
    }

    Matcher invalid() => throwsA(
      isA<BackupException>().having((e) => e.code, 'code', 'verify_failed'),
    );

    test('detecta un byte cambiado', () async {
      await exportSome();
      final text = target.readAsStringSync();
      target.writeAsStringSync(text.replaceFirst('Física', 'Fisica'));
      await expectLater(verifyBackupFile(target), invalid());
    });

    test('detecta un archivo truncado (sin pie)', () async {
      await exportSome();
      final lines = target.readAsLinesSync();
      target.writeAsStringSync('${lines.take(3).join('\n')}\n');
      await expectLater(verifyBackupFile(target), invalid());
    });

    test('detecta un archivo cortado a mitad de línea', () async {
      await exportSome();
      final bytes = target.readAsBytesSync();
      target.writeAsBytesSync(bytes.sublist(0, bytes.length - 10));
      await expectLater(verifyBackupFile(target), invalid());
    });

    test('rechaza archivos vacíos o ajenos', () async {
      target.writeAsStringSync('');
      await expectLater(verifyBackupFile(target), invalid());
      target.writeAsStringSync('{"hola":1}\n{"kind":"footer"}\n');
      await expectLater(verifyBackupFile(target), invalid());
      target.writeAsBytesSync([0xff, 0xfe, 0x0a]);
      await expectLater(verifyBackupFile(target), invalid());
    });

    test('rechaza una versión de formato futura', () async {
      writeSealed(target, [
        {...header(), 'formatVersion': backupFormatVersion + 1},
      ]);
      await expectLater(verifyBackupFile(target), invalid());
    });

    test('detecta ids duplicados', () async {
      const id = '0190f5c2-0000-7000-8000-000000000001';
      writeSealed(target, [
        header(),
        row('notebooks', {'id': id, 'title': 'A'}),
        row('notebooks', {'id': id, 'title': 'B'}),
      ]);
      await expectLater(verifyBackupFile(target), invalid());
    });

    test('detecta relaciones rotas', () async {
      writeSealed(target, [
        header(),
        row('notes', {
          'id': '0190f5c2-0000-7000-8000-000000000002',
          'notebook_id': '0190f5c2-0000-7000-8000-000000000009',
        }),
      ]);
      await expectLater(verifyBackupFile(target), invalid());
    });

    test('acepta un archivo sellado correctamente', () async {
      const nb = '0190f5c2-0000-7000-8000-000000000001';
      writeSealed(target, [
        header(),
        row('notebooks', {'id': nb, 'title': 'A'}),
        row('notes', {
          'id': '0190f5c2-0000-7000-8000-000000000002',
          'notebook_id': nb,
          'content': '',
        }),
      ]);
      final check = await verifyBackupFile(target);
      expect(check.counts, {'notebooks': 1, 'notes': 1, 'drawings': 0});
      expect(check.warnings, isEmpty);
    });
  });

  group('versiones del esquema', () {
    test('una base de la versión 1 se migra y se exporta como 2', () async {
      await db.close();
      final file = File('${dir.path}/v1.sqlite');
      db = LocalDatabase(
        NativeDatabase(
          file,
          setup: (raw) {
            final version = raw.select('PRAGMA user_version').first.values;
            if (version.first == 0) {
              raw.execute('CREATE TABLE notebooks (id TEXT PRIMARY KEY)');
              raw.execute('CREATE TABLE pages (id TEXT PRIMARY KEY)');
              raw.execute('CREATE TABLE strokes (id TEXT PRIMARY KEY)');
              raw.execute("INSERT INTO notebooks VALUES ('lab')");
              raw.execute('PRAGMA user_version = 1');
            }
          },
        ),
      );
      final summary = await exporter().exportTo(target);
      expect(summary.schemaVersion, 2);
      expect(summary.counts['notebooks'], 0); // la v1 eran datos de prueba
      await verifyBackupFile(target);
    });

    test('una base de una versión futura no se exporta', () async {
      await LocalNotebooksRepository(db).create('Física');
      await db.customStatement('PRAGMA user_version = 3');
      await expectLater(
        exporter().exportTo(target),
        throwsA(
          isA<BackupException>().having(
            (e) => e.code,
            'code',
            'unsupported_schema',
          ),
        ),
      );
      expect(files(), isEmpty);
    });

    test('una tabla desconocida con datos detiene la copia', () async {
      await db.customStatement('CREATE TABLE pages (id TEXT)');
      await db.customStatement("INSERT INTO pages VALUES ('p1')");
      await expectLater(
        exporter().exportTo(target),
        throwsA(
          isA<BackupException>().having((e) => e.code, 'code', 'unknown_table'),
        ),
      );
      expect(files(), isEmpty);
    });

    test('una tabla desconocida vacía no molesta', () async {
      await db.customStatement('CREATE TABLE pages (id TEXT)');
      await exporter().exportTo(target);
      await verifyBackupFile(target);
    });
  });

  test('nombre sugerido', () {
    expect(
      suggestedBackupName(DateTime(2026, 3, 4, 5, 6)),
      'euler-notes-20260304-0506.eulernotes',
    );
  });
}
