import 'package:euler_notes/core/server_settings.dart';
import 'package:euler_notes/features/notes/data/note_drafts.dart';
import 'package:euler_notes/features/notes/presentation/note_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_backend.dart';

void main() {
  group('NoteDrafts', () {
    late SharedPreferences preferences;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      preferences = await SharedPreferences.getInstance();
    });

    NoteDraft draft(String content) => NoteDraft(
      title: 'T',
      content: content,
      base: 'antes',
      savedAt: DateTime(2026, 11, 5, 14, 30),
    );

    test('guarda, lee y borra por nota', () async {
      final drafts = NoteDrafts(preferences, 'http://pc:8000');
      await drafts.write(3, draft('nuevo'));
      final read = drafts.read(3)!;
      expect(read.content, 'nuevo');
      expect(read.base, 'antes');
      expect(read.savedAt, DateTime(2026, 11, 5, 14, 30));
      expect(drafts.read(4), isNull);
      await drafts.remove(3);
      expect(drafts.read(3), isNull);
    });

    test('cada servidor tiene sus propios borradores', () async {
      await NoteDrafts(preferences, 'http://a:8000').write(1, draft('de A'));
      expect(NoteDrafts(preferences, 'http://b:8000').read(1), isNull);
    });

    test('sin almacenamiento no falla', () async {
      final drafts = NoteDrafts(null, 'http://pc:8000');
      await drafts.write(1, draft('x'));
      expect(drafts.read(1), isNull);
    });

    test('un borrador corrupto se ignora', () {
      expect(NoteDraft.fromJson('no es json'), isNull);
      expect(NoteDraft.fromJson('{"title": 1}'), isNull);
    });
  });

  group('editor sin conexión', () {
    late FakeBackend backend;
    late int noteId;
    late SharedPreferences preferences;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      preferences = await SharedPreferences.getInstance();
      backend = FakeBackend();
      final notebookId = backend.addNotebook('Física');
      noteId = backend.addNote(notebookId, 'Energía', content: 'Inicio');
    });

    Iterable<String> draftKeys() =>
        preferences.getKeys().where((k) => k.startsWith('note_draft'));

    Future<void> openEditor(WidgetTester tester) async {
      await pumpApp(
        tester,
        backend,
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      );
      await tester.tap(find.text('Física'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Energía'));
      await tester.pumpAndSettle();
    }

    /// Simula que Android cierra la app: se desmonta todo el árbol.
    Future<void> killApp(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }

    Finder content() => find.byKey(const Key('note-content'));
    String contentText(WidgetTester tester) =>
        tester.widget<TextField>(content()).controller!.text;

    Future<void> writeOffline(WidgetTester tester, String text) async {
      await openEditor(tester);
      backend.offline = true;
      await tester.enterText(content(), text);
      await tester.pump(NoteEditorScreen.autosaveDelay);
      await tester.pumpAndSettle();
      expect(find.text('Error al guardar'), findsOneWidget);
      expect(draftKeys(), hasLength(1));
    }

    testWidgets('el texto sobrevive al cierre de la app y se recupera', (
      tester,
    ) async {
      await writeOffline(tester, 'Teorema trabajo-energía');
      await killApp(tester);
      expect(backend.notes[noteId]!['content'], 'Inicio');

      backend.offline = false;
      await openEditor(tester);
      expect(find.text('Cambios sin guardar'), findsOneWidget);
      await tester.tap(find.text('Recuperar'));
      await tester.pumpAndSettle();
      expect(contentText(tester), 'Teorema trabajo-energía');

      await tester.pump(NoteEditorScreen.autosaveDelay);
      await tester.pumpAndSettle();
      expect(backend.notes[noteId]!['content'], 'Teorema trabajo-energía');
      expect(draftKeys(), isEmpty);
    });

    testWidgets('descartar el borrador deja la versión del servidor', (
      tester,
    ) async {
      await writeOffline(tester, 'Borrador');
      await killApp(tester);

      backend.offline = false;
      await openEditor(tester);
      await tester.tap(find.text('Descartar'));
      await tester.pumpAndSettle();
      expect(contentText(tester), 'Inicio');
      expect(draftKeys(), isEmpty);
    });

    testWidgets('avisa si la nota cambió en el servidor desde el borrador', (
      tester,
    ) async {
      await writeOffline(tester, 'Mi versión');
      await killApp(tester);

      backend.offline = false;
      backend.notes[noteId]!['content'] = 'Editada en otro sitio';
      await openEditor(tester);
      expect(find.textContaining('también cambió en el servidor'), findsOneWidget);
      await tester.tap(find.text('Descartar'));
      await tester.pumpAndSettle();
    });

    testWidgets('reintenta solo al volver la conexión', (tester) async {
      await writeOffline(tester, 'Sin red');
      backend.offline = false;
      await tester.pump(NoteEditorScreen.retryDelays.first);
      await tester.pumpAndSettle();
      expect(find.text('Guardado'), findsOneWidget);
      expect(backend.notes[noteId]!['content'], 'Sin red');
      expect(draftKeys(), isEmpty);
    });
  });
}
