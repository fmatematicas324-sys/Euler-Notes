import 'package:cuaderno_cientifico/core/api_client.dart';
import 'package:cuaderno_cientifico/features/notes/presentation/markdown_preview.dart';
import 'package:cuaderno_cientifico/features/plot/presentation/plot_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_backend.dart';

Future<void> _pump(WidgetTester tester, String data) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(body: MarkdownPreview(data: data)),
  ),
);

List<Math> _formulas(WidgetTester tester) =>
    tester.widgetList<Math>(find.byType(Math)).toList();

void main() {
  testWidgets('fórmula en línea dentro de un párrafo', (tester) async {
    await _pump(tester, r'La energía es $E = mc^2$ en reposo.');
    final math = _formulas(tester).single;
    expect(math.mathStyle, MathStyle.text);
    expect(find.textContaining('La energía es'), findsOneWidget);
  });

  testWidgets(r'bloque $$ en una línea y en varias', (tester) async {
    await _pump(
      tester,
      '\$\$\\int x^2\\,dx\$\$\n\nTexto\n\n\$\$\n\\frac{a}{b}\n\$\$',
    );
    final formulas = _formulas(tester);
    expect(formulas, hasLength(2));
    expect(formulas.every((m) => m.mathStyle == MathStyle.display), isTrue);
    expect(find.text('Texto'), findsOneWidget);
  });

  testWidgets('los precios con espacio no se interpretan como fórmulas', (
    tester,
  ) async {
    await _pump(tester, r'Cuesta $ 5 y $ 10.');
    expect(find.byType(Math), findsNothing);
  });

  testWidgets('LaTeX inválido muestra el texto fuente sin fallar', (
    tester,
  ) async {
    await _pump(tester, r'$\frac{1}$');
    expect(tester.takeException(), isNull);
    expect(find.textContaining(r'\frac{1}'), findsOneWidget);
  });

  testWidgets('bloque ```plot se muestra como gráfica', (tester) async {
    final backend = FakeBackend();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [httpClientProvider.overrideWithValue(backend.client)],
        child: const MaterialApp(
          home: Scaffold(
            body: MarkdownPreview(
              data: 'Antes\n\n```plot\nsin(x)\nx: -pi, pi\n```\n\nDespués',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PlotView), findsOneWidget);
    expect(find.text('Antes'), findsOneWidget);
    expect(find.text('Después'), findsOneWidget);
    expect(backend.plotRequests.single['exprs'], ['sin(x)']);
  });

  testWidgets('bloque ```plot inválido muestra el motivo', (tester) async {
    await _pump(tester, '```plot\nx\nx: 3, 1\n```');
    expect(find.byType(PlotView), findsNothing);
    expect(find.textContaining('Gráfica no válida'), findsOneWidget);
  });

  testWidgets('otros bloques de código no son gráficas', (tester) async {
    await _pump(tester, '```python\nprint(1)\n```');
    expect(find.byType(PlotView), findsNothing);
    expect(find.textContaining('print(1)'), findsOneWidget);
  });

  testWidgets('Markdown sin fórmulas y contenido vacío', (tester) async {
    await _pump(tester, '# Título\n\n- uno\n- dos');
    expect(find.text('Título'), findsOneWidget);
    expect(find.byType(Math), findsNothing);

    await _pump(tester, '   ');
    expect(find.text('La vista previa aparecerá aquí'), findsOneWidget);
  });
}
