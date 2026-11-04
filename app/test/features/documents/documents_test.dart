import 'dart:typed_data';

import 'package:euler_notes/features/documents/data/documents_repository.dart';
import 'package:euler_notes/features/documents/presentation/document_viewer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_backend.dart';

final _pdf = Uint8List.fromList('%PDF-1.7 prueba'.codeUnits);

void main() {
  late FakeBackend backend;
  late int noteId;
  var picks = 0;

  setUp(() {
    backend = FakeBackend();
    final notebookId = backend.addNotebook('Física');
    noteId = backend.addNote(notebookId, 'Electromagnetismo', content: 'Notas');
    picks = 0;
  });

  Future<void> openEditor(WidgetTester tester) async {
    await pumpApp(
      tester,
      backend,
      overrides: [
        pdfPickerProvider.overrideWithValue(() async {
          picks++;
          return (name: 'maxwell.pdf', bytes: _pdf);
        }),
        // pdfium no existe en los tests: un marcador ocupa el lugar del visor.
        pdfViewerBuilderProvider.overrideWithValue(
          (data, name, controller, onPageChanged) =>
              Center(child: Text('Visor: $name (${data.length} B)')),
        ),
      ],
    );
    await tester.tap(find.text('Física'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Electromagnetismo'));
    await tester.pumpAndSettle();
  }

  Future<void> openLibrary(WidgetTester tester) async {
    await tester.tap(find.text('PDF'));
    await tester.pumpAndSettle();
  }

  String content(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const Key('note-content')))
      .controller!
      .text;

  Future<void> backToEditor(WidgetTester tester) async {
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1)); // autoguardado
    await tester.pumpAndSettle();
  }

  testWidgets('importar un PDF lo sube y abre el visor', (tester) async {
    await openEditor(tester);
    await openLibrary(tester);
    expect(find.text('Aún no hay PDF'), findsOneWidget);

    await tester.tap(find.text('Importar PDF'));
    await tester.pumpAndSettle();

    expect(picks, 1);
    expect(backend.documentFiles.values.single, _pdf);
    expect(find.text('Visor: maxwell.pdf (${_pdf.length} B)'), findsOneWidget);
    expect(find.text('Página 1 de 2'), findsOneWidget);
    expect(find.text('Página 1: ∫ x² dx'), findsOneWidget);
    await backToEditor(tester);
  });

  testWidgets('insertar la página como cita con la fuente', (tester) async {
    await openEditor(tester);
    await openLibrary(tester);
    await tester.tap(find.text('Importar PDF'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Insertar página como cita'));
    await tester.pumpAndSettle();
    expect(find.text('Insertado en la nota'), findsOneWidget);

    await backToEditor(tester);
    expect(
      content(tester),
      'Notas\n\n> Página 1: ∫ x² dx\n>\n> — *maxwell.pdf*, p. 1\n',
    );
    expect(backend.notes[noteId]!['content'], content(tester));
  });

  testWidgets('LaTeX: insertar la selección como fórmula', (tester) async {
    await openEditor(tester);
    await openLibrary(tester);
    await tester.tap(find.text('Importar PDF'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('LaTeX'));
    await tester.pumpAndSettle();
    expect(find.text('Selecciona una fórmula'), findsOneWidget);

    const latex = r'Página 1: \int x^{2} dx';
    final start = latex.indexOf(r'\int');
    tester
        .widget<SelectableText>(find.byKey(const Key('page-text')))
        .onSelectionChanged!(
      TextSelection(baseOffset: start, extentOffset: latex.length),
      null,
    );
    await tester.pump();
    await tester.tap(find.text('Insertar como fórmula'));
    await tester.pumpAndSettle();

    await backToEditor(tester);
    expect(content(tester), 'Notas\n\n\$\$\\int x^{2} dx\$\$\n');
  });

  testWidgets('cambiar de página pide su texto', (tester) async {
    await openEditor(tester);
    await openLibrary(tester);
    await tester.tap(find.text('Importar PDF'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Página siguiente'));
    await tester.pumpAndSettle();
    expect(find.text('Página 2 de 2'), findsOneWidget);
    expect(find.text('Página 2: ∫ x² dx'), findsOneWidget);
    expect(backend.pageTextRequests, [1, 2]);

    final next = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_right),
    );
    expect(next.onPressed, isNull);
    await backToEditor(tester);
  });

  testWidgets('la biblioteca lista, abre y elimina PDF', (tester) async {
    backend
      ..documents[90] = {
        'id': 90,
        'filename': 'ondas.pdf',
        'size': 2048,
        'pages': 1,
        'created_at': '2026-11-03T10:00:00Z',
      }
      ..documentFiles[90] = _pdf;
    await openEditor(tester);
    await openLibrary(tester);
    expect(find.text('ondas.pdf'), findsOneWidget);
    expect(find.text('1 página · 2,0 KB'), findsOneWidget);

    await tester.tap(find.byTooltip('Eliminar PDF'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
    await tester.pumpAndSettle();
    expect(find.text('ondas.pdf'), findsNothing);
    expect(backend.documents, isEmpty);
  });

  testWidgets('un PDF inválido muestra el error del backend', (tester) async {
    backend.uploadError = (
      422,
      'invalid_pdf',
      'El archivo no es un PDF válido o está dañado',
    );
    await openEditor(tester);
    await openLibrary(tester);
    await tester.tap(find.text('Importar PDF'));
    await tester.pumpAndSettle();

    expect(
      find.text('El archivo no es un PDF válido o está dañado'),
      findsOneWidget,
    );
    expect(find.text('Biblioteca de PDF'), findsOneWidget);
  });
}
