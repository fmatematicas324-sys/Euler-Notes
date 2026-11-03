import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_backend.dart';

void main() {
  late FakeBackend backend;
  late int notebookId;

  setUp(() {
    backend = FakeBackend();
    notebookId = backend.addNotebook('Física');
  });

  Future<void> openNotebook(WidgetTester tester) async {
    await pumpApp(tester, backend);
    await tester.tap(find.text('Física'));
    await tester.pumpAndSettle();
  }

  testWidgets('lista las notas del cuaderno', (tester) async {
    backend
      ..addNote(notebookId, 'Cinemática')
      ..addNote(notebookId, 'Dinámica');
    await openNotebook(tester);

    expect(find.text('Cinemática'), findsOneWidget);
    expect(find.text('Dinámica'), findsOneWidget);
  });

  testWidgets('crear una nota abre el editor y vuelve a la lista', (
    tester,
  ) async {
    await openNotebook(tester);
    expect(find.text('Este cuaderno está vacío'), findsOneWidget);

    await tester.tap(find.text('Nueva nota'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Ondas');
    await tester.pump();
    await tester.tap(find.text('Crear'));
    await tester.pumpAndSettle();

    // Editor abierto con el título de la nota.
    expect(find.byKey(const Key('note-content')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('note-title')))
          .controller!
          .text,
      'Ondas',
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note-content')), findsNothing);
    expect(find.text('Ondas'), findsOneWidget);
  });

  testWidgets('eliminar una nota', (tester) async {
    backend.addNote(notebookId, 'Borrador');
    await openNotebook(tester);

    await tester.tap(find.byTooltip('Eliminar nota'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
    await tester.pumpAndSettle();

    expect(find.text('Borrador'), findsNothing);
    expect(backend.notes, isEmpty);
  });
}
