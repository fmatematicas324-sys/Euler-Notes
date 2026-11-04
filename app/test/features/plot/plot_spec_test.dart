import 'dart:math' as math;

import 'package:cuaderno_cientifico/features/plot/domain/plot_spec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlotSpec.parse', () {
    test('una expresión con valores por defecto', () {
      final spec = PlotSpec.parse('sin(x)');
      expect(spec.exprs, ['sin(x)']);
      expect(spec.variable, 'x');
      expect((spec.xMin, spec.xMax), (-10.0, 10.0));
      expect(spec.yMin, isNull);
    });

    test('varias expresiones, rangos con pi, comentarios y líneas vacías', () {
      final spec = PlotSpec.parse('''
# trigonometría
sin(x)

cos(x)
x: -2pi, 2pi
y: -1.5, 1.5
''');
      expect(spec.exprs, ['sin(x)', 'cos(x)']);
      expect(spec.xMin, closeTo(-2 * math.pi, 1e-12));
      expect(spec.xMax, closeTo(2 * math.pi, 1e-12));
      expect((spec.yMin, spec.yMax), (-1.5, 1.5));
    });

    test('otra variable con su propio rango', () {
      final spec = PlotSpec.parse('var: t\nt^2\nt: 0 5');
      expect(spec.variable, 't');
      expect((spec.xMin, spec.xMax), (0.0, 5.0));
    });

    test('límites con pi: -pi, 0.5*pi, π', () {
      final spec = PlotSpec.parse('x\nx: -pi, 0.5*pi');
      expect(spec.xMin, closeTo(-math.pi, 1e-12));
      expect(spec.xMax, closeTo(math.pi / 2, 1e-12));
      expect(PlotSpec.parse('x\nx: 0, π').xMax, closeTo(math.pi, 1e-12));
    });

    for (final (source, message) in [
      ('', 'al menos una expresión'),
      ('# solo comentario', 'al menos una expresión'),
      (List.filled(6, 'x').join('\n'), 'Como máximo 5'),
      ('x\nx: 5, 1', 'el mínimo debe ser menor'),
      ('x\nx: a, b', 'no es un número'),
      ('x\nx: 1', 'mínimo, máximo'),
      ('x\nz: 1, 2', 'Opción desconocida: z'),
      ('x\nvar: _t', 'Variable no válida'),
    ]) {
      test('error: «${source.replaceAll('\n', r'\n')}»', () {
        expect(
          () => PlotSpec.parse(source),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains(message),
            ),
          ),
        );
      });
    }
  });

  test('toRequestJson incluye y solo si hay rango', () {
    const spec = PlotSpec(exprs: ['x']);
    final json = spec.toRequestJson(
      dark: true,
      width: 600,
      height: 300,
      scale: 2,
    );
    expect(json, {
      'exprs': ['x'],
      'var': 'x',
      'x_min': -10.0,
      'x_max': 10.0,
      'theme': 'dark',
      'width': 600,
      'height': 300,
      'scale': 2.0,
    });
    const withY = PlotSpec(exprs: ['x'], yMin: -1, yMax: 1);
    expect(
      withY.toRequestJson(dark: false, width: 1, height: 1, scale: 1),
      containsPair('y_min', -1.0),
    );
  });

  test('igualdad por valor', () {
    expect(PlotSpec.parse('sin(x)\nx: 0, 1'), PlotSpec.parse('sin(x)\nx:0,1'));
    expect(PlotSpec.parse('sin(x)'), isNot(PlotSpec.parse('cos(x)')));
  });
}
