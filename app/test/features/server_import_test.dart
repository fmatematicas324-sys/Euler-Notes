import 'dart:convert';

import 'package:drift/native.dart';
import 'package:euler_notes/core/api_client.dart';
import 'package:euler_notes/core/local_db/local_database.dart';
import 'package:euler_notes/features/sync/server_import.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_backend.dart';

const _server = 'http://pc:8000';

void main() {
  group('bloques ```ink', () {
    const markdown =
        '# Tema\n\nTexto con id: 5 fuera del bloque.\n\n'
        '```ink\nid: 7\n```\n\n'
        '```plot\nsin(x)\n```\n\n'
        '```ink\n  id : 9  \n```';

    test('encuentra solo los ids de los bloques ink', () {
      expect(inkDrawingIds(markdown), [7, 9]);
    });

    test('reescribe los ids conocidos y conserva el resto', () {
      final out = rewriteInkIds(markdown, {7: 'uuid-7'});
      expect(out, contains('```ink\nid: uuid-7\n```'));
      expect(out, contains('  id : 9  ')); // sin correspondencia
      expect(out, contains('id: 5 fuera del bloque')); // fuera de ink
      expect(out.split('\n'), hasLength(markdown.split('\n').length));
    });
  });

  group('ServerImporter', () {
    late FakeBackend backend;
    late LocalDatabase db;
    late ServerImporter importer;
    late int physics;
    late int energy;
    late int drawingId;

    setUp(() {
      backend = FakeBackend();
      physics = backend.addNotebook('Física', cover: 'ocean');
      final math = backend.addNotebook('Cálculo');
      energy = backend.addNote(physics, 'Energía', paper: 'grid');
      backend.addNote(math, 'Límites', content: r'$\lim_{x\to0}$');
      drawingId = 1000;
      backend.drawings[drawingId] = {
        'id': drawingId,
        'note_id': energy,
        'width': 800.0,
        'height': 600.0,
        'strokes': [
          {
            'tool': 'pen',
            'color': '#1c64d9',
            'width': 2.5,
            'points': [1.0, 2.0, 0.5, 3.0, 4.0, 0.6],
          },
        ],
        'created_at': '2026-11-03T10:00:00+00:00',
        'updated_at': '2026-11-03T10:00:00+00:00',
      };
      backend.notes[energy]!['content'] =
          'W = ΔK\n\n```ink\nid: $drawingId\n```\n\n```ink\nid: 404\n```';
      db = LocalDatabase(NativeDatabase.memory());
      importer = ServerImporter(
        ApiClient(backend.client, baseUrl: _server),
        db,
        _server,
      );
    });

    tearDown(() => db.close());

    test('copia cuadernos, notas y dibujos y lo verifica', () async {
      final report = await importer.run();
      expect(report.verified, isTrue, reason: report.mismatches.join('\n'));
      expect(
        (report.notebooks, report.notes, report.drawings),
        (2, 2, 1),
      );
      expect(report.created, 5);

      final notebook = await (db.select(
        db.notebooks,
      )..where((n) => n.sourceId.equals(physics))).getSingle();
      expect(notebook.title, 'Física');
      expect(notebook.cover, 'ocean');
      expect(notebook.source, _server);

      final note = await (db.select(
        db.notes,
      )..where((n) => n.sourceId.equals(energy))).getSingle();
      expect(note.notebookId, notebook.id);
      expect(note.paper, 'grid');

      final drawing = await db.select(db.drawings).getSingle();
      expect(drawing.noteId, note.id);
      expect(drawing.width, 800);
      expect(
        jsonDecode(drawing.strokes),
        backend.drawings[drawingId]!['strokes'],
      );
      // El bloque ink apunta ahora al UUID local; el que no existe, intacto.
      expect(note.content, contains('```ink\nid: ${drawing.id}\n```'));
      expect(note.content, contains('id: 404'));
    });

    test('avisa de los dibujos que faltan en el servidor', () async {
      final report = await importer.run();
      expect(report.warnings, hasLength(1));
      expect(report.warnings.single, contains('404'));
    });

    test('repetir la importación no duplica y actualiza los cambios', () async {
      await importer.run();
      final firstIds = (await db.select(db.notes).get()).map((n) => n.id).toSet();

      backend.notes[energy]!['title'] = 'Energía mecánica';
      final report = await importer.run();
      expect(report.created, 0);
      expect(report.updated, 5);
      expect(report.verified, isTrue);

      final notes = await db.select(db.notes).get();
      expect(notes.map((n) => n.id).toSet(), firstIds);
      expect(notes.map((n) => n.title), contains('Energía mecánica'));
      expect(await db.select(db.drawings).get(), hasLength(1));
    });

    test('si el servidor no responde, la copia local no cambia', () async {
      backend.offline = true;
      await expectLater(importer.run(), throwsA(anything));
      expect(await db.select(db.notebooks).get(), isEmpty);
      expect(await db.select(db.notes).get(), isEmpty);
    });

    test('el servidor no recibe ninguna escritura', () async {
      String snapshot() => jsonEncode([
        backend.notebooks.values.toList(),
        backend.notes.values.toList(),
        backend.drawings.values.toList(),
      ]);
      final before = snapshot();
      await importer.run();
      expect(snapshot(), before);
    });
  });
}
