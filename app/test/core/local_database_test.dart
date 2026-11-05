import 'dart:math';
import 'dart:typed_data';

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

    Future<String> addNotebook() async {
      final id = uuidV7();
      await db
          .into(db.notebooks)
          .insert(
            NotebooksCompanion.insert(
              id: id,
              title: 'Física',
              createdAt: 1,
              updatedAt: 1,
            ),
          );
      return id;
    }

    test('crea el esquema y activa las claves foráneas', () async {
      expect(await db.scalar('PRAGMA foreign_keys'), '1');
      final page = PagesCompanion.insert(
        id: uuidV7(),
        notebookId: 'no-existe',
        title: 'Huérfana',
        position: 0,
        createdAt: 1,
        updatedAt: 1,
      );
      await expectLater(db.into(db.pages).insert(page), throwsA(anything));
    });

    test('guarda y recupera la tinta como Float32', () async {
      final notebookId = await addNotebook();
      final pageId = uuidV7();
      await db
          .into(db.pages)
          .insert(
            PagesCompanion.insert(
              id: pageId,
              notebookId: notebookId,
              title: 'Tinta',
              position: 0,
              createdAt: 1,
              updatedAt: 1,
            ),
          );
      final points = Float32List.fromList([10, 20, 0.5, 0, 11, 21, 0.6, 8]);
      await db
          .into(db.strokes)
          .insert(
            StrokesCompanion.insert(
              id: uuidV7(),
              pageId: pageId,
              tool: 'pen',
              color: 0xFF000000,
              width: 2,
              minX: 10,
              minY: 20,
              maxX: 11,
              maxY: 21,
              points: points.buffer.asUint8List(),
              createdAt: 1,
            ),
          );
      final stored = await db.select(db.strokes).getSingle();
      final restored = Float32List.view(
        Uint8List.fromList(stored.points).buffer,
      );
      expect(restored, points);
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
      expect(await db.select(db.pages).get(), isEmpty);
      expect(await db.select(db.strokes).get(), isEmpty);
    });
  });
}
