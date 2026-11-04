import 'package:cuaderno_cientifico/features/notes/presentation/note_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_backend.dart';

void main() {
  late FakeBackend backend;
  late int noteId;

  setUp(() {
    backend = FakeBackend();
    final notebookId = backend.addNotebook('Física');
    noteId = backend.addNote(notebookId, 'Energía', content: 'Inicio');
  });

  Future<void> openEditor(WidgetTester tester, {Size? size}) async {
    await pumpApp(tester, backend, size: size ?? const Size(1280, 800));
    await tester.tap(find.text('Física'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Energía'));
    await tester.pumpAndSettle();
  }

  Finder content() => find.byKey(const Key('note-content'));
  String contentText(WidgetTester tester) =>
      tester.widget<TextField>(content()).controller!.text;

  /// Las figuras piden su imagen en un temporizador: hay que avanzar el reloj.
  Future<void> pumpFigures(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
  }

  Future<void> waitAutosave(WidgetTester tester) async {
    await tester.pump(NoteEditorScreen.autosaveDelay);
    await tester.pumpAndSettle();
  }

  testWidgets('vista previa en vivo con LaTeX y autoguardado', (tester) async {
    await openEditor(tester);
    expect(find.text('Guardado'), findsOneWidget);

    await tester.enterText(
      content(),
      r'# Relatividad'
      '\n\n'
      r'$E = mc^2$',
    );
    await tester.pump();
    expect(find.text('Sin guardar'), findsOneWidget);
    // Layout ancho: vista previa al lado, con la fórmula renderizada.
    expect(find.byType(Math), findsOneWidget);
    expect(find.text('Relatividad'), findsOneWidget);

    await waitAutosave(tester);
    expect(find.text('Guardado'), findsOneWidget);
    expect(
      backend.notes[noteId]!['content'],
      r'# Relatividad'
      '\n\n'
      r'$E = mc^2$',
    );
  });

  testWidgets('el título se guarda y un título vacío no se envía', (
    tester,
  ) async {
    await openEditor(tester);
    final title = find.byKey(const Key('note-title'));

    await tester.enterText(title, 'Energía cinética');
    await waitAutosave(tester);
    expect(backend.notes[noteId]!['title'], 'Energía cinética');

    await tester.enterText(title, '   ');
    await waitAutosave(tester);
    expect(backend.notes[noteId]!['title'], 'Energía cinética');
  });

  testWidgets('al salir se guardan los cambios pendientes', (tester) async {
    await openEditor(tester);
    await tester.enterText(content(), 'Cambio rápido');
    await tester.pump();

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(backend.notes[noteId]!['content'], 'Cambio rápido');
    expect(content(), findsNothing);
  });

  testWidgets('botones de fórmula envuelven la selección', (tester) async {
    await openEditor(tester);
    final controller = tester.widget<TextField>(content()).controller!;
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 6);

    await tester.tap(find.text(r'$ $ Fórmula'));
    await tester.pump();
    expect(contentText(tester), r'$Inicio$');
    await waitAutosave(tester);
  });

  testWidgets('botón Gráfica inserta un bloque plot que se muestra', (
    tester,
  ) async {
    await openEditor(tester);
    final controller = tester.widget<TextField>(content()).controller!;
    controller.selection = const TextSelection.collapsed(offset: 6);

    await tester.tap(find.text('Gráfica'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gráfica de función'));
    await tester.pumpAndSettle();
    await pumpFigures(tester);

    expect(
      contentText(tester),
      'Inicio\n\n```plot\nsin(x)\nx: -2pi, 2pi\n```\n',
    );
    expect(backend.plotRequests.single['exprs'], ['sin(x)']);
    await waitAutosave(tester);
  });

  testWidgets('menú Gráfica inserta plantillas de diagrama', (tester) async {
    await openEditor(tester);
    final controller = tester.widget<TextField>(content()).controller!;
    controller.selection = const TextSelection.collapsed(offset: 6);

    await tester.tap(find.text('Gráfica'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cuerpo libre'));
    await tester.pumpAndSettle();
    await pumpFigures(tester);

    expect(contentText(tester), contains('```diagram\ntipo: fuerzas\n'));
    expect(backend.diagramRequests.single['kind'], 'forces');
    await waitAutosave(tester);
  });

  testWidgets('panel de cálculo: representación visual al insertar', (
    tester,
  ) async {
    await openEditor(tester);
    await tester.tap(find.text('Calcular').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('compute-expr')), 'x^3 - 3x');
    await tester.tap(find.byKey(const Key('compute-run')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Insertar como bloque'));
    await tester.pumpAndSettle();

    expect(
      contentText(tester),
      endsWith(
        '```diagram\ntipo: funcion\nf: x^3 - 3x\nop: derivar\n'
        'x: -10, 10\n```\n',
      ),
    );
    expect(backend.diagramRequests.single, containsPair('op', 'diff'));
    await waitAutosave(tester);
  });

  testWidgets('panel de cálculo: sin representación visual si se desactiva', (
    tester,
  ) async {
    await openEditor(tester);
    await tester.tap(find.text('Calcular').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('compute-expr')), 'x^2');
    await tester.tap(find.byKey(const Key('compute-visual')));
    await tester.tap(find.byKey(const Key('compute-run')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Insertar en línea'));
    await tester.pumpAndSettle();

    expect(contentText(tester), r'Inicio$2 x$');
    await waitAutosave(tester);
  });

  testWidgets('teclado de símbolos inserta LaTeX en el cursor', (tester) async {
    await openEditor(tester);
    final controller = tester.widget<TextField>(content()).controller!;
    controller.selection = const TextSelection.collapsed(offset: 6);

    await tester.tap(find.text('Símbolos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vectores'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('symbol-Divergencia')));
    await tester.pump();

    expect(contentText(tester), r'Inicio$\nabla \cdot \vec{}$');
    expect(
      controller.selection.baseOffset,
      'Inicio\$\\nabla \\cdot \\vec{'.length,
    );

    await tester.tap(find.text('Símbolos'));
    await tester.pumpAndSettle();
    expect(find.text('Vectores'), findsNothing);
    await waitAutosave(tester);
  });

  testWidgets('panel de cálculo: calcular e insertar como bloque', (
    tester,
  ) async {
    backend.onCompute = (_) => (
      200,
      {
        'result_latex': r'x \cos{\left(x \right)} + \sin{\left(x \right)}',
        'result_text': 'x*cos(x) + sin(x)',
      },
    );
    await openEditor(tester);

    await tester.tap(find.text('Calcular').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('compute-expr')), 'sin(x)*x');
    await tester.tap(find.byKey(const Key('compute-visual')));
    await tester.tap(find.byKey(const Key('compute-run')));
    await tester.pumpAndSettle();

    expect(backend.computeRequests.single, {
      'expr': 'sin(x)*x',
      'op': 'diff',
      'var': 'x',
    });
    expect(find.text('x*cos(x) + sin(x)'), findsOneWidget);

    await tester.tap(find.text('Insertar como bloque'));
    await tester.pumpAndSettle();

    expect(
      contentText(tester),
      'Inicio\n\n\$\$x \\cos{\\left(x \\right)} + \\sin{\\left(x \\right)}\$\$\n',
    );
    expect(find.byType(Math), findsOneWidget);
    await waitAutosave(tester);
  });

  testWidgets('panel de cálculo: muestra errores del backend', (tester) async {
    backend.onCompute = (_) => (
      400,
      {
        'error': {
          'code': 'invalid_expression',
          'message': 'La expresión contiene caracteres no permitidos',
        },
      },
    );
    await openEditor(tester);

    await tester.tap(find.text('Calcular').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('compute-expr')), 'x; y');
    await tester.tap(find.byKey(const Key('compute-run')));
    await tester.pumpAndSettle();

    expect(
      find.text('La expresión contiene caracteres no permitidos'),
      findsOneWidget,
    );
    expect(find.text('Insertar como bloque'), findsNothing);
  });

  testWidgets('pantalla estrecha usa pestañas Editar / Vista previa', (
    tester,
  ) async {
    await openEditor(tester, size: const Size(400, 800));
    expect(find.text('Editar'), findsOneWidget);

    await tester.enterText(content(), r'$$\int x^2\,dx$$');
    await tester.tap(find.text('Vista previa'));
    await tester.pumpAndSettle();
    expect(find.byType(Math), findsOneWidget);
    await waitAutosave(tester);
  });
}
