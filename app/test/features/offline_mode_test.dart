import 'package:drift/native.dart';
import 'package:euler_notes/core/api_client.dart';
import 'package:euler_notes/core/local_db/local_database.dart';
import 'package:euler_notes/core/local_db/local_database_provider.dart';
import 'package:euler_notes/core/server_settings.dart';
import 'package:euler_notes/features/ink/data/local_drawings_repository.dart';
import 'package:euler_notes/features/ink/domain/stroke.dart';
import 'package:euler_notes/features/notebooks/data/local_notebooks_repository.dart';
import 'package:euler_notes/features/notebooks/domain/notebook_cover.dart';
import 'package:euler_notes/features/notes/data/local_notes_repository.dart';
import 'package:euler_notes/features/notes/domain/paper_style.dart';
import 'package:euler_notes/features/notes/presentation/note_editor_screen.dart';
import 'package:euler_notes/features/sync/server_import.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_backend.dart';

void main() {
  late LocalDatabase db;

  setUp(() => db = LocalDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('repositorios locales', () {
    test('cuadernos: crear, ordenar, renombrar y borrar', () async {
      final repo = LocalNotebooksRepository(db);
      final a = await repo.create('Física', cover: NotebookCover.physics);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final b = await repo.create('Cálculo');
      expect((await repo.list()).map((n) => n.title), ['Cálculo', 'Física']);
      expect(a.cover, NotebookCover.physics);

      await Future<void>.delayed(const Duration(milliseconds: 2));
      final renamed = await repo.update(a.id, title: 'Física I');
      expect(renamed.title, 'Física I');
      expect((await repo.list()).first.id, a.id); // el más reciente primero

      await repo.delete(b.id);
      expect((await repo.list()).map((n) => n.title), ['Física I']);
    });

    test('notas: crear, leer, guardar y borrar', () async {
      final notebook = await LocalNotebooksRepository(db).create('Física');
      final repo = LocalNotesRepository(db);
      final note = await repo.create(notebook.id, 'Energía');
      expect(note.content, '');
      expect(note.paper, PaperStyle.blank);

      await repo.update(note.id, content: r'$W = \Delta K$');
      await repo.update(note.id, paper: PaperStyle.grid);
      final read = await repo.get(note.id);
      expect(read.content, r'$W = \Delta K$');
      expect(read.paper, PaperStyle.grid);
      expect(read.title, 'Energía');

      expect(await repo.list(notebook.id), hasLength(1));
      await repo.delete(note.id);
      expect(await repo.list(notebook.id), isEmpty);
      await expectLater(repo.get(note.id), throwsA(anything));
    });

    test('borrar un cuaderno oculta sus notas', () async {
      final notebooks = LocalNotebooksRepository(db);
      final notes = LocalNotesRepository(db);
      final notebook = await notebooks.create('Física');
      final note = await notes.create(notebook.id, 'Energía');
      await notebooks.delete(notebook.id);
      await expectLater(notes.get(note.id), throwsA(anything));
    });

    test('dibujos: crear y guardar trazos', () async {
      final notebook = await LocalNotebooksRepository(db).create('Física');
      final note = await LocalNotesRepository(db).create(notebook.id, 'Tinta');
      final repo = LocalDrawingsRepository(db);
      final drawing = await repo.create(note.id);
      expect((drawing.width, drawing.height), (1000.0, 700.0));
      expect(drawing.strokes, isEmpty);

      final stroke = Stroke.fromJson(const {
        'tool': 'pen',
        'color': '#1c64d9',
        'width': 2.5,
        'points': [1.0, 2.0, 0.5, 3.0, 4.0, 0.6],
      });
      await repo.saveStrokes(drawing.id, [stroke]);
      final read = await repo.get(drawing.id);
      expect(read.strokes.single.toJson(), stroke.toJson());
    });
  });

  group('importar después de trabajar sin conexión', () {
    late FakeBackend backend;
    late int energy;

    ServerImporter importer() => ServerImporter(
      ApiClient(backend.client, baseUrl: 'http://pc:8000'),
      db,
      'http://pc:8000',
    );

    setUp(() {
      backend = FakeBackend();
      final physics = backend.addNotebook('Física');
      energy = backend.addNote(physics, 'Energía', content: 'Servidor');
    });

    test('no pisa una nota editada en la tablet', () async {
      await importer().run();
      final repo = LocalNotesRepository(db);
      final local = (await db.select(db.notes).get()).single;
      await repo.update(local.id, content: 'Escrito sin conexión');

      final report = await importer().run();
      expect(report.kept, 1);
      expect(report.verified, isTrue);
      expect((await repo.get(local.id)).content, 'Escrito sin conexión');
      expect(backend.notes[energy]!['content'], 'Servidor');
    });

    test('no resucita una nota borrada en la tablet', () async {
      await importer().run();
      final local = (await db.select(db.notes).get()).single;
      await LocalNotesRepository(db).delete(local.id);

      final report = await importer().run();
      expect(report.kept, 1);
      final notebook = (await db.select(db.notebooks).get()).single;
      expect(await LocalNotesRepository(db).list(notebook.id), isEmpty);
    });
  });

  group('la app en modo sin conexión', () {
    late FakeBackend backend;
    late SharedPreferences preferences;

    setUp(() async {
      SharedPreferences.setMockInitialValues({'offline_mode': true});
      preferences = await SharedPreferences.getInstance();
      // El servidor está apagado: todo debe funcionar igual.
      backend = FakeBackend()..offline = true;
    });

    Future<void> openApp(WidgetTester tester) => pumpApp(
      tester,
      backend,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        localDatabaseProvider.overrideWithValue(db),
      ],
    );

    testWidgets('crear un cuaderno y una nota sin servidor', (tester) async {
      await openApp(tester);
      expect(find.byKey(const Key('offline-indicator')), findsOneWidget);
      expect(find.text('Aún no tienes cuadernos'), findsOneWidget);

      await tester.tap(find.text('Nuevo cuaderno'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Física');
      await tester.pump();
      await tester.tap(find.text('Crear'));
      await tester.pumpAndSettle();
      expect(find.text('Física'), findsOneWidget);

      await tester.tap(find.text('Física'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nueva nota'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Ondas');
      await tester.pump();
      await tester.tap(find.text('Crear'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('note-content')),
        r'$v = \lambda f$',
      );
      await tester.pump(NoteEditorScreen.autosaveDelay);
      await tester.pumpAndSettle();
      expect(find.text('Guardado'), findsOneWidget);

      final note = (await db.select(db.notes).get()).single;
      expect(note.title, 'Ondas');
      expect(note.content, r'$v = \lambda f$');
      expect(backend.notebooks, isEmpty); // nada llegó al servidor
    });

    testWidgets('abre las notas importadas con sus dibujos', (tester) async {
      final online = FakeBackend();
      final physics = online.addNotebook('Física');
      final note = online.addNote(physics, 'Energía');
      online.drawings[500] = {
        'id': 500,
        'note_id': note,
        'width': 1000.0,
        'height': 700.0,
        'strokes': <Object>[],
        'created_at': '2026-11-03T10:00:00+00:00',
        'updated_at': '2026-11-03T10:00:00+00:00',
      };
      online.notes[note]!['content'] = 'Texto\n\n```ink\nid: 500\n```';
      await ServerImporter(
        ApiClient(online.client, baseUrl: 'http://pc:8000'),
        db,
        'http://pc:8000',
      ).run();
      final drawing = (await db.select(db.drawings).get()).single;

      await openApp(tester);
      await tester.tap(find.text('Física'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Energía'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('ink-preview-${drawing.id}')), findsOneWidget);
      expect(find.textContaining('Dibujo no válido'), findsNothing);
    });
  });
}
