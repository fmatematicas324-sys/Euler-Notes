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
}
