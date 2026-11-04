import 'package:cuaderno_cientifico/features/notebooks/domain/notebook_cover.dart';
import 'package:cuaderno_cientifico/features/notebooks/presentation/notebook_cover_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_backend.dart';

void main() {
  late FakeBackend backend;
  setUp(() => backend = FakeBackend());

  testWidgets('estado vacío y creación de un cuaderno', (tester) async {
    await pumpApp(tester, backend);
    expect(find.text('Aún no tienes cuadernos'), findsOneWidget);
    expect(find.byTooltip('Backend conectado (v0.1.0)'), findsOneWidget);

    await tester.tap(find.text('Nuevo cuaderno'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  Física  ');
    await tester.pump();
    await tester.tap(find.text('Crear'));
    await tester.pumpAndSettle();

    expect(find.text('Física'), findsOneWidget);
    expect(backend.notebooks.values.single['title'], 'Física');
  });

  testWidgets('el botón Crear está desactivado con título vacío', (
    tester,
  ) async {
    await pumpApp(tester, backend);
    await tester.tap(find.text('Nuevo cuaderno'));
    await tester.pumpAndSettle();
    final create = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Crear'),
    );
    expect(create.onPressed, isNull);
  });

  testWidgets('renombrar un cuaderno', (tester) async {
    backend.addNotebook('Fisica');
    await pumpApp(tester, backend);

    await tester.tap(find.byTooltip('Opciones'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Renombrar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Física II');
    await tester.pump();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('Física II'), findsOneWidget);
    expect(find.text('Fisica'), findsNothing);
  });

  testWidgets('eliminar pide confirmación', (tester) async {
    final id = backend.addNotebook('Química');
    backend.addNote(id, 'Enlaces');
    await pumpApp(tester, backend);

    await tester.tap(find.byTooltip('Opciones'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('todas sus notas'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Química'), findsOneWidget);

    await tester.tap(find.byTooltip('Opciones'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
    await tester.pumpAndSettle();

    expect(find.text('Química'), findsNothing);
    expect(backend.notebooks, isEmpty);
    expect(backend.notes, isEmpty);
  });

  testWidgets('sin backend muestra error y permite reintentar', (tester) async {
    backend.offline = true;
    await pumpApp(tester, backend);
    expect(find.textContaining('No se pudo conectar'), findsOneWidget);

    backend
      ..offline = false
      ..addNotebook('Álgebra');
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('Álgebra'), findsOneWidget);
  });

  testWidgets('crear un cuaderno con portada', (tester) async {
    await pumpApp(tester, backend);
    await tester.tap(find.text('Nuevo cuaderno'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Cosmos');
    await tester.tap(find.byKey(const Key('cover-sagan')));
    await tester.pump();
    await tester.tap(find.text('Crear'));
    await tester.pumpAndSettle();

    expect(backend.notebooks.values.single['cover'], 'sagan');
    final card = tester.widget<NotebookCoverCard>(
      find.byType(NotebookCoverCard),
    );
    expect(card.notebook.cover, NotebookCover.sagan);
  });

  testWidgets('cambiar la portada', (tester) async {
    backend.addNotebook('Cálculo II', cover: 'classic');
    await pumpApp(tester, backend);

    await tester.tap(find.byTooltip('Opciones'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cambiar portada'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cover-calculus')));
    await tester.pumpAndSettle();

    final notebook = backend.notebooks.values.single;
    expect(notebook['cover'], 'calculus');
    expect(notebook['title'], 'Cálculo II');
  });

  testWidgets('una portada desconocida se muestra como clásica', (
    tester,
  ) async {
    backend.addNotebook('Futuro', cover: 'holograma');
    await pumpApp(tester, backend);
    final card = tester.widget<NotebookCoverCard>(
      find.byType(NotebookCoverCard),
    );
    expect(card.notebook.cover, NotebookCover.classic);
  });

  testWidgets('estantería en cuadrícula con todas las portadas', (
    tester,
  ) async {
    for (final cover in NotebookCover.values) {
      backend.addNotebook(cover.label, cover: cover.id);
    }
    await pumpApp(tester, backend, size: const Size(1400, 1000));
    expect(
      find.byType(NotebookCoverCard),
      findsNWidgets(NotebookCover.values.length),
    );
    expect(tester.takeException(), isNull);
  });
}
