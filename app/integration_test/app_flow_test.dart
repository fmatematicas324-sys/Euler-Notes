// Prueba de punta a punta contra el backend real (http://127.0.0.1:8000).
//
//   cd backend && CUADERNO_COMPUTE_TIMEOUT=15 \
//       .venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000
//
// (límite de cálculo amplio: la prueba verifica el flujo, no el rendimiento,
// y en máquinas cargadas una gráfica puede superar los 5 s por defecto)
//   cd app && flutter test integration_test -d linux \
//       [--dart-define=SCREENSHOT_DIR=/ruta/capturas] \
//       [--dart-define=SAMPLE_PDF=/ruta/a/un.pdf]   (activa los pasos de PDF)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cuaderno_cientifico/app.dart';
import 'package:cuaderno_cientifico/features/documents/data/documents_repository.dart';
import 'package:cuaderno_cientifico/features/notebooks/presentation/notebook_cover_card.dart';
import 'package:cuaderno_cientifico/features/notes/presentation/markdown_preview.dart';
import 'package:cuaderno_cientifico/features/plot/presentation/figure_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _screenshotDir = String.fromEnvironment('SCREENSHOT_DIR');
const _samplePdf = String.fromEnvironment('SAMPLE_PDF');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final boundaryKey = GlobalKey();

  Future<void> waitFor(
    WidgetTester tester,
    Finder finder, {
    bool present = true,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (finder.evaluate().isEmpty == present) {
      if (DateTime.now().isAfter(deadline)) {
        throw TestFailure('Tiempo agotado esperando: $finder');
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  Future<void> screenshot(WidgetTester tester, String name) async {
    if (_screenshotDir.isEmpty) return;
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$_screenshotDir/$name.png')
          .writeAsBytes(png!.buffer.asUint8List());
    });
  }

  Future<void> createWithDialog(
    WidgetTester tester,
    String button,
    String title,
  ) async {
    await tester.tap(find.text(button));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      title,
    );
    await tester.pump();
    await tester.tap(find.text('Crear'));
  }

  // Busca el elemento de una lista: `find.text` también encontraría el texto
  // dentro de un TextField (el diálogo de creación o el título del editor).
  Finder listItem(String title) => find.widgetWithText(ListTile, title);
  Finder notebookItem(String title) =>
      find.widgetWithText(NotebookCoverCard, title);

  /// Imagen ya cargada de la figura número [index] de la vista previa,
  /// desplazando la vista previa hasta ella (las que no se ven no se construyen).
  Future<void> waitForFigure(WidgetTester tester, int index) async {
    final preview = find.descendant(
      of: find.byType(MarkdownPreview),
      matching: find.byType(Scrollable),
    );
    final figure = find.byType(FigureView);
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (figure.evaluate().length <= index) {
      if (DateTime.now().isAfter(deadline)) {
        throw TestFailure('No apareció la figura $index');
      }
      await tester.drag(preview.first, const Offset(0, -200));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.ensureVisible(figure.at(index));
    await waitFor(
      tester,
      find.descendant(of: figure.at(index), matching: find.byType(Image)),
      timeout: const Duration(seconds: 30),
    );
  }

  testWidgets(
    'flujo completo: cuaderno → nota → LaTeX → cálculo → figuras → PDF',
    (tester) async {
      final notebookTitle = 'E2E ${DateTime.now().millisecondsSinceEpoch}';
      final content = find.byKey(const Key('note-content'));

      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: ProviderScope(
            overrides: [
              if (_samplePdf.isNotEmpty)
                pdfPickerProvider.overrideWithValue(
                  () async => (
                    name: 'muestra.pdf',
                    bytes: await File(_samplePdf).readAsBytes(),
                  ),
                ),
            ],
            child: const CuadernoApp(),
          ),
        ),
      );
      await waitFor(
        tester,
        find.byWidgetPredicate(
          (w) =>
              w is Tooltip && (w.message ?? '').startsWith('Backend conectado'),
        ),
      );
      await screenshot(tester, '01_inicio');

      // 1. Crear cuaderno.
      await createWithDialog(tester, 'Nuevo cuaderno', notebookTitle);
      await waitFor(tester, notebookItem(notebookTitle));
      await screenshot(tester, '02_cuadernos');

      // 2. Abrir cuaderno y crear nota (abre el editor).
      await tester.tap(notebookItem(notebookTitle));
      await waitFor(tester, find.text('Este cuaderno está vacío'));
      await createWithDialog(tester, 'Nueva nota', 'Relatividad');
      await waitFor(tester, content);

      // 3. Markdown + LaTeX con vista previa en vivo.
      await tester.enterText(
        content,
        '# Energía\n\n'
        r'En reposo: $E = mc^2$'
        '\n\n'
        r'$$\int x^2\,dx$$'
        '\n',
      );
      await tester.pumpAndSettle();
      expect(find.byType(Math), findsNWidgets(2));
      expect(find.text('Energía'), findsOneWidget);

      // 4. Cálculo simbólico real con SymPy e inserción en la nota.
      await tester.tap(find.text('Calcular').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('compute-expr')), 'sin(x)*x');
      await tester.tap(find.byKey(const Key('compute-run')));
      await waitFor(tester, find.text('x*cos(x) + sin(x)'));
      await screenshot(tester, '03_calculo');

      // Con la representación visual activada se añade su diagrama.
      await tester.tap(find.text('Insertar como bloque'));
      await tester.pumpAndSettle();
      expect(find.byType(Math), findsNWidgets(3));
      await waitForFigure(tester, 0);

      // 5. Gráfica (bloque ```plot) y diagrama de cuerpo libre (plantilla).
      await tester.tap(find.text('Gráfica'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gráfica de función'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gráfica'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cuerpo libre'));
      await tester.pumpAndSettle();
      await waitForFigure(tester, 1);
      await waitForFigure(tester, 2);

      // 6. Papel milimetrado.
      await tester.tap(find.byTooltip('Papel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Milimetrado'));
      await tester.pumpAndSettle();

      // 7. PDF: importar, leer (pdfium real) e insertar una cita.
      if (_samplePdf.isNotEmpty) {
        await tester.tap(find.text('PDF'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Importar PDF'));
        await waitFor(tester, find.text('Página 1 de 2'));
        await waitFor(tester, find.byKey(const Key('page-text')));
        await tester.pump(const Duration(seconds: 2)); // páginas de pdfium
        await screenshot(tester, '06_pdf');
        await tester.tap(find.text('Insertar página como cita'));
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
      await waitFor(tester, find.text('Guardado'));
      await screenshot(tester, '04_editor');

      // 8. Volver, reabrir y comprobar que se guardó en el backend.
      await tester.pageBack();
      await waitFor(tester, listItem('Relatividad'));
      await screenshot(tester, '05_notas');
      await tester.tap(listItem('Relatividad'));
      await waitFor(tester, content);
      final saved = tester.widget<TextField>(content).controller!.text;
      expect(
        saved,
        contains(r'$$x \cos{\left(x \right)} + \sin{\left(x \right)}$$'),
      );
      expect(saved, contains(r'$E = mc^2$'));
      expect(saved, contains('```plot\nsin(x)\nx: -2pi, 2pi\n```'));
      expect(saved, contains('```diagram\ntipo: funcion\nf: sin(x)*x'));
      expect(saved, contains('```diagram\ntipo: fuerzas'));
      if (_samplePdf.isNotEmpty) {
        expect(saved, contains('> — *muestra.pdf*, p. 1'));
      }

      // 9. Limpieza: eliminar el cuaderno (y sus notas en cascada).
      await tester.pageBack();
      await waitFor(tester, listItem('Relatividad'));
      await tester.pageBack();
      await waitFor(tester, notebookItem(notebookTitle));
      await tester.tap(
        find.descendant(
          of: notebookItem(notebookTitle),
          matching: find.byTooltip('Opciones'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
      await waitFor(tester, notebookItem(notebookTitle), present: false);
    },
  );
}
