import 'package:cuaderno_cientifico/features/ink/presentation/ink_canvas.dart';
import 'package:cuaderno_cientifico/features/ink/presentation/ink_editor_screen.dart';
import 'package:cuaderno_cientifico/features/ink/presentation/ink_preview.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_backend.dart';

void main() {
  late FakeBackend backend;
  late int noteId;

  setUp(() {
    backend = FakeBackend();
    final notebookId = backend.addNotebook('Física');
    noteId = backend.addNote(notebookId, 'Problema 3', content: 'Enunciado');
  });

  Future<void> openEditor(WidgetTester tester) async {
    await pumpApp(tester, backend);
    await tester.tap(find.text('Física'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Problema 3'));
    await tester.pumpAndSettle();
  }

  Future<void> stylusStroke(WidgetTester tester) async {
    final origin = tester.getTopLeft(find.byType(InkCanvas));
    tester.binding.handlePointerEvent(
      PointerDownEvent(
        pointer: 9,
        kind: PointerDeviceKind.stylus,
        position: origin + const Offset(20, 20),
        pressure: 0.3,
        pressureMin: 0,
        pressureMax: 1,
      ),
    );
    for (var i = 1; i <= 5; i++) {
      tester.binding.handlePointerEvent(
        PointerMoveEvent(
          pointer: 9,
          kind: PointerDeviceKind.stylus,
          position: origin + Offset(20 + i * 20.0, 20 + i * 10.0),
          pressure: 0.3 + i * 0.1,
          pressureMin: 0,
          pressureMax: 1,
        ),
      );
    }
    tester.binding.handlePointerEvent(
      PointerUpEvent(
        pointer: 9,
        kind: PointerDeviceKind.stylus,
        position: origin + const Offset(120, 70),
      ),
    );
    await tester.pump();
  }

  testWidgets('insertar un dibujo, trazar con lápiz y verlo en la nota', (
    tester,
  ) async {
    await openEditor(tester);
    await tester.tap(find.text('Dibujo'));
    await tester.pumpAndSettle();

    // Editor de dibujo abierto y bloque insertado en la nota.
    expect(find.byType(InkEditorScreen), findsOneWidget);
    final drawingId = backend.drawings.keys.single;
    expect(backend.drawings[drawingId]!['note_id'], noteId);

    await stylusStroke(tester);
    expect(find.textContaining('Lápiz detectado'), findsOneWidget);
    await tester.pump(InkEditorScreen.autosaveDelay);
    await tester.pumpAndSettle();
    expect(find.text('Guardado'), findsOneWidget);

    final saved = backend.drawings[drawingId]!['strokes'] as List<dynamic>;
    final points = (saved.single as Map)['points'] as List<dynamic>;
    expect(points.length, 18); // 6 puntos × (x, y, presión)
    expect(points[2], 0.3);
    expect(points.last, 0.8);

    await tester.pageBack();
    await tester.pumpAndSettle();
    final content = tester
        .widget<TextField>(find.byKey(const Key('note-content')))
        .controller!
        .text;
    expect(content, 'Enunciado\n\n```ink\nid: $drawingId\n```\n');
    expect(find.byType(InkPreview), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });

  testWidgets('deshacer, rehacer y borrar todo desde el editor', (
    tester,
  ) async {
    await openEditor(tester);
    await tester.tap(find.text('Dibujo'));
    await tester.pumpAndSettle();
    await stylusStroke(tester);

    await tester.tap(find.byTooltip('Deshacer (Ctrl+Z)'));
    await tester.pump();
    await tester.tap(find.byTooltip('Rehacer (Ctrl+Y)'));
    await tester.pump();
    await tester.tap(find.byTooltip('Borrar todo'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Borrar'));
    await tester.pumpAndSettle();
    await tester.pump(InkEditorScreen.autosaveDelay);
    await tester.pumpAndSettle();

    expect(backend.drawings.values.single['strokes'], isEmpty);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });

  testWidgets('tocar la vista previa abre el dibujo', (tester) async {
    backend.drawings[77] = {
      'id': 77,
      'note_id': noteId,
      'width': 1000.0,
      'height': 700.0,
      'strokes': [
        {
          'tool': 'pen',
          'color': '#1C64D9',
          'width': 3.0,
          'points': [10.0, 10.0, 0.5, 200.0, 100.0, 0.7],
        },
      ],
      'created_at': '2026-11-04T10:00:00Z',
      'updated_at': '2026-11-04T10:00:00Z',
    };
    backend.notes[noteId]!['content'] = 'Esquema:\n\n```ink\nid: 77\n```\n';
    await openEditor(tester);
    expect(find.byType(InkPreview), findsOneWidget);

    await tester.tap(find.byKey(const Key('ink-preview-77')));
    await tester.pumpAndSettle();
    expect(find.byType(InkEditorScreen), findsOneWidget);
    expect(find.byTooltip('Deshacer (Ctrl+Z)'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
  });
}
