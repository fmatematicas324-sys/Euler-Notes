import 'dart:math' as math;

import 'package:euler_notes/features/plot/domain/diagram_spec.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _json(DiagramSpec spec) => spec.toRequestJson(
  dark: false,
  width: 600,
  height: 300,
  scale: 1,
)..removeWhere((k, _) => {'theme', 'width', 'height', 'scale'}.contains(k));

void main() {
  test('función con operación en español y rango con pi', () {
    final spec = DiagramSpec.parse(
      'tipo: Función\nf: sin(x)\nop: Resolver\nx: -2pi, 2pi',
    );
    expect(spec.endpoint, '/diagram');
    final json = _json(spec);
    expect(json['kind'], 'function');
    expect(json['op'], 'solve');
    expect(json['x_max'] as double, closeTo(2 * math.pi, 1e-12));
  });

  test('función: valores por defecto y otra variable', () {
    final json = _json(DiagramSpec.parse('tipo: funcion\nf: t^2\nvar: t'));
    expect(json, {
      'kind': 'function',
      'expr': 't^2',
      'op': 'diff',
      'var': 't',
      'x_min': -10.0,
      'x_max': 10.0,
    });
  });

  test('fuerzas con etiquetas con acentos y resultante oculta', () {
    final json = _json(
      DiagramSpec.parse(
        'tipo: fuerzas\nFricción: 2.5, 180\nPeso: 9.8, 270\nresultante: no',
      ),
    );
    expect(json['show_resultant'], false);
    expect(json['forces'], [
      {'label': 'Fricción', 'magnitude': 2.5, 'angle': 180.0},
      {'label': 'Peso', 'magnitude': 9.8, 'angle': 270.0},
    ]);
  });

  test('proyectil con valores por defecto', () {
    final json = _json(
      DiagramSpec.parse('tipo: tiro parabólico\nv0: 15\nángulo: 30'),
    );
    expect(json, {
      'kind': 'projectile',
      'v0': 15.0,
      'angle': 30.0,
      'g': 9.81,
      'h0': 0.0,
    });
  });

  test('grafo: -> lo hace dirigido y admite pesos', () {
    final json = _json(DiagramSpec.parse('tipo: grafo\nA -> B: 3\nB - C'));
    expect(json['directed'], true);
    expect(json['edges'], [
      {'source': 'A', 'target': 'B', 'weight': 3.0},
      {'source': 'B', 'target': 'C', 'weight': null},
    ]);
    expect(
      _json(DiagramSpec.parse('tipo: grafo\nA - B\ndirigido: sí'))['directed'],
      true,
    );
  });

  for (final (source, message) in [
    ('f: x', 'Indica el tipo'),
    ('tipo: circuito', 'Tipo desconocido'),
    ('tipo: funcion\nop: derivar', 'Falta la función'),
    ('tipo: funcion\nf: x\nop: factorizar', 'Operación desconocida'),
    ('tipo: funcion\nf: x\ncolor: rojo', 'Opción desconocida'),
    ('tipo: fuerzas', 'al menos una fuerza'),
    ('tipo: fuerzas\nF: 10', 'módulo, ángulo'),
    ('tipo: fuerzas\nF: -1, 0', 'positivo'),
    ('tipo: fuerzas\nF: 9,8, 270', 'módulo, ángulo'),
    (
      r'tipo: fuerzas'
          '\n'
          r'$F$: 1, 0',
      'Nombre no válido',
    ),
    ('tipo: proyectil\nv0: 10', 'angulo'),
    ('tipo: proyectil\nv0: 10\nangulo: 95', 'entre 0 y 90'),
    ('tipo: grafo\nA B', 'Arista no válida'),
  ]) {
    test('error: ${source.replaceAll('\n', ' | ')}', () {
      expect(
        () => DiagramSpec.parse(source),
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

  test('functionBlock genera un bloque que se puede volver a leer', () {
    final block = DiagramSpec.functionBlock(expr: 'sin(x)*x', op: 'diff');
    expect(
      block,
      '```diagram\ntipo: funcion\nf: sin(x)*x\nop: derivar\nx: -2pi, 2pi\n```',
    );
    final inner = block
        .split('\n')
        .skip(1)
        .takeWhile((l) => l != '```')
        .join('\n');
    expect(_json(DiagramSpec.parse(inner))['op'], 'diff');

    expect(
      DiagramSpec.functionBlock(expr: 't^2', op: 'solve', variable: 't'),
      contains('op: resolver\nvar: t\nt: -10, 10'),
    );
  });

  test('las plantillas del editor son válidas', () {
    for (final block in DiagramSpec.templates.values) {
      final inner = block
          .split('\n')
          .skip(1)
          .takeWhile((l) => l != '```')
          .join('\n');
      expect(() => DiagramSpec.parse(inner), returnsNormally, reason: block);
    }
  });

  test('igualdad por contenido', () {
    expect(
      DiagramSpec.parse('tipo: grafo\nA - B'),
      DiagramSpec.parse('tipo: grafo\n\nA  -  B'),
    );
  });
}
