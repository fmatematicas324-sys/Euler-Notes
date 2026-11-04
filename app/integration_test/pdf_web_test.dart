// Visor de PDF en Web (pdfium WASM) contra el backend real. Necesita un PDF
// ya importado cuyo nombre se pasa en PDF_NAME:
//
//   curl -X POST "http://127.0.0.1:8001/documents?filename=muestra-web.pdf" \
//        -H "Content-Type: application/pdf" --data-binary @un.pdf
//   chromedriver --port=4444 &
//   cd app && flutter drive -d web-server --browser-name=chrome --headless \
//       --driver=test_driver/integration_test.dart \
//       --target=integration_test/pdf_web_test.dart \
//       --dart-define=API_BASE_URL=http://127.0.0.1:8001 \
//       --dart-define=PDF_NAME=muestra-web.pdf
import 'package:cuaderno_cientifico/app.dart';
import 'package:cuaderno_cientifico/features/notebooks/presentation/notebook_cover_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';

const _pdfName = String.fromEnvironment(
  'PDF_NAME',
  defaultValue: 'muestra-web.pdf',
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Paso actual: el driver lo guarda aunque falle (los errores en Web no
  /// llegan con su mensaje).
  var currentStep = 'inicio';
  void step(String name) {
    currentStep = name;
    binding.reportData = {'paso': name};
  }

  Future<void> waitFor(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 40),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (finder.evaluate().isEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        throw TestFailure('Tiempo agotado esperando: $finder');
      }
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('Web: abrir un PDF, verlo con pdfium e insertar una cita', (
    tester,
  ) async {
    // En Web el texto entra por un <input> del navegador: el teclado simulado
    // de flutter_test debe registrarse para que `enterText` funcione.
    binding.testTextInput.register();
    try {
      final title = 'Web ${DateTime.now().millisecondsSinceEpoch}';
      await tester.pumpWidget(const ProviderScope(child: CuadernoApp()));
      await waitFor(tester, find.byTooltip('Backend conectado (v0.1.0)'));

      // Cuaderno y nota.
      step('crear cuaderno y nota');
      await tester.tap(find.text('Nuevo cuaderno'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), title);
      await tester.pump();
      await tester.tap(find.text('Crear'));
      await waitFor(tester, find.widgetWithText(NotebookCoverCard, title));
      await tester.tap(find.widgetWithText(NotebookCoverCard, title));
      await waitFor(tester, find.text('Nueva nota'));
      await tester.tap(find.text('Nueva nota'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Lecturas');
      await tester.pump();
      await tester.tap(find.text('Crear'));
      await waitFor(tester, find.byKey(const Key('note-content')));

      // Abrir el PDF desde la biblioteca.
      step('abrir biblioteca');
      await tester.tap(find.text('PDF'));
      await waitFor(tester, find.text(_pdfName));
      step('abrir PDF');
      await tester.tap(find.text(_pdfName));
      await waitFor(tester, find.byType(PdfViewer));
      await waitFor(tester, find.byKey(const Key('page-text')));

      // Dar tiempo a pdfium (WASM) para dibujar la página.
      step('esperar pdfium');
      final controller = tester
          .widget<PdfViewer>(find.byType(PdfViewer))
          .controller!;
      final deadline = DateTime.now().add(const Duration(seconds: 40));
      while (!controller.isReady) {
        if (DateTime.now().isAfter(deadline)) {
          throw TestFailure('pdfium no cargó el documento');
        }
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(controller.pageCount, 2);
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      step('captura 1');
      await binding.takeScreenshot('web_pdf');

      // Página siguiente desde el panel: el visor la sigue.
      step('página 2');
      await tester.tap(find.byTooltip('Página siguiente'));
      await waitFor(tester, find.text('Página 2 de 2'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      await binding.takeScreenshot('web_pdf_p2');

      step('insertar cita');
      await tester.tap(find.text('Insertar página como cita'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      final content = tester
          .widget<TextField>(find.byKey(const Key('note-content')))
          .controller!
          .text;
      expect(content, contains('— *$_pdfName*, p. 2'));
      expect(content, contains('∂'));
      step('fin');
    } catch (error, stack) {
      try {
        await binding.takeScreenshot('web_fallo');
      } on Object catch (_) {}
      binding.reportData = {
        'paso': currentStep,
        'error': error.toString(),
        'traza': stack.toString().split('\n').take(6).join('\n'),
      };
      rethrow;
    }
  });
}
