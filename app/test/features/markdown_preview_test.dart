import 'package:cuaderno_cientifico/features/notes/presentation/markdown_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';

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

  testWidgets('Markdown sin fórmulas y contenido vacío', (tester) async {
    await _pump(tester, '# Título\n\n- uno\n- dos');
    expect(find.text('Título'), findsOneWidget);
    expect(find.byType(Math), findsNothing);

    await _pump(tester, '   ');
    expect(find.text('La vista previa aparecerá aquí'), findsOneWidget);
  });
}
