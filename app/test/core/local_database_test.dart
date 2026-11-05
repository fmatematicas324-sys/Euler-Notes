import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:euler_notes/core/local_db/local_database.dart';
import 'package:euler_notes/core/local_db/uuid_v7.dart';
import 'package:euler_notes/features/lab/storage_benchmark.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('uuidV7', () {
    final pattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );

    test('formato RFC 9562: versión 7 y variante', () {
      for (var i = 0; i < 50; i++) {
        expect(uuidV7(), matches(pattern));
      }
    });

    test('codifica la fecha y se ordena por ella', () {
      final early = uuidV7(now: DateTime.utc(2026, 1, 1), random: Random(1));
      final later = uuidV7(now: DateTime.utc(2026, 11, 5), random: Random(1));
      expect(early.compareTo(later), lessThan(0));
      expect(uuidV7Time(later), DateTime.utc(2026, 11, 5).toLocal());
    });

    test('sin colisiones en el mismo milisegundo', () {
      final now = DateTime(2026, 11, 5);
      final ids = {for (var i = 0; i < 1000; i++) uuidV7(now: now)};
      expect(ids, hasLength(1000));
    });
  });

  group('LocalDatabase', () {
    late LocalDatabase db;

    setUp(() => db = LocalDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<String> addNotebook({String? source, int? sourceId}) async {
      final id = uuidV7();
      await db
          .into(db.notebooks)
          .insert(
            NotebooksCompanion.insert(
              id: id,
              source: Value(source),
              sourceId: Value(sourceId),
              title: 'Física',
              createdAt: 1,
              updatedAt: 1,
            ),
          );
      return id;
    }

    test('crea el esquema y activa las claves foráneas', () async {
      expect(await db.scalar('PRAGMA foreign_keys'), '1');
      final note = NotesCompanion.insert(
        id: uuidV7(),
        notebookId: 'no-existe',
        title: 'Huérfana',
        createdAt: 1,
        updatedAt: 1,
      );
      await expectLater(db.into(db.notes).insert(note), throwsA(anything));
    });

    test('un mismo origen no se puede importar dos veces', () async {
      await addNotebook(source: 'http://pc:8000', sourceId: 1);
      await expectLater(
        addNotebook(source: 'http://pc:8000', sourceId: 1),
        throwsA(anything),
      );
      // Otro servidor, o una fila creada en la tablet (sin origen), sí.
      await addNotebook(source: 'http://otro:8000', sourceId: 1);
      await addNotebook();
      await addNotebook();
      expect(await db.select(db.notebooks).get(), hasLength(4));
    });

    test('guarda los trazos de un dibujo tal cual', () async {
      final notebookId = await addNotebook();
      final noteId = uuidV7();
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: noteId,
              notebookId: notebookId,
              title: 'Tinta',
              createdAt: 1,
              updatedAt: 1,
            ),
          );
      const strokes = '[{"tool":"pen","color":"#000000","width":2.0,'
          '"points":[1.0,2.0,0.5]}]';
      await db
          .into(db.drawings)
          .insert(
            DrawingsCompanion.insert(
              id: uuidV7(),
              noteId: noteId,
              width: 800,
              height: 600,
              strokes: const Value(strokes),
              createdAt: 1,
              updatedAt: 1,
            ),
          );
      final stored = await db.select(db.drawings).getSingle();
      expect(stored.strokes, strokes);
    });

    test('el banco de pruebas mide todo y deja la base vacía', () async {
      final steps = <String>[];
      final results = await runStorageBenchmark(
        db,
        size: BenchmarkSize.tiny,
        onProgress: steps.add,
      );
      final labels = results.map((r) => r.label).join('\n');
      expect(labels, contains('Autoguardado'));
      expect(labels, contains('Guardar un trazo'));
      expect(labels, contains('FTS5'));
      expect(
        results.firstWhere((r) => r.label.contains('FTS5')).ok,
        isTrue,
        reason: 'SQLite debe incluir FTS5',
      );
      expect(steps, isNotEmpty);
      expect(await db.select(db.notebooks).get(), isEmpty);
      expect(await db.select(db.notes).get(), isEmpty);
      expect(await db.select(db.drawings).get(), isEmpty);
    });
  });

  test('migra la base del laboratorio de la Misión 014 (versión 1)', () async {
    // Esquema v1 tal como quedó en la tablet tras el laboratorio.
    final old = LocalDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw
            ..execute('CREATE TABLE notebooks (id TEXT PRIMARY KEY, title TEXT)')
            ..execute('CREATE TABLE pages (id TEXT PRIMARY KEY)')
            ..execute('CREATE TABLE strokes (id TEXT PRIMARY KEY)')
            ..execute('PRAGMA user_version = 1');
        },
      ),
    );
    addTearDown(old.close);
    expect(await old.scalar('PRAGMA user_version'), '2');
    final tables = await old
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .map((row) => row.read<String>('name'))
        .get();
    expect(tables, containsAll(['notebooks', 'notes', 'drawings']));
    expect(tables, isNot(contains('pages')));
    expect(tables, isNot(contains('strokes')));
    await old.into(old.notebooks).insert(
      NotebooksCompanion.insert(
        id: uuidV7(),
        title: 'Nueva',
        createdAt: 1,
        updatedAt: 1,
      ),
    );
  });
}
