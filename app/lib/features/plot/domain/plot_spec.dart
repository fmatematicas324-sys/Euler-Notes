import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Qué dibujar: expresiones, variable y rangos. El tamaño, el tema y la
/// densidad de píxeles los decide el widget que la muestra.
@immutable
class PlotSpec {
  const PlotSpec({
    required this.exprs,
    this.variable = 'x',
    this.xMin = -10,
    this.xMax = 10,
    this.yMin,
    this.yMax,
  });

  static const maxExpressions = 5;

  /// Interpreta el contenido de un bloque ` ```plot `:
  ///
  /// ```plot
  /// sin(x)          ← una expresión por línea (máx. 5)
  /// x^2/10
  /// x: -2pi, 2pi    ← rango de la variable (opcional, por defecto -10, 10)
  /// y: -2, 2        ← rango de y (opcional, automático si se omite)
  /// var: t          ← variable (opcional, por defecto x)
  /// ```
  ///
  /// Las líneas vacías y las que empiezan por `#` se ignoran. Lanza
  /// [FormatException] con un mensaje para el usuario si algo no es válido.
  factory PlotSpec.parse(String source) {
    final exprs = <String>[];
    final settings = <String, String>{};
    for (final raw in source.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final setting = _setting.firstMatch(line);
      if (setting != null) {
        settings[setting[1]!.toLowerCase()] = setting[2]!.trim();
      } else {
        exprs.add(line);
      }
    }

    final variable = settings.remove('var') ?? 'x';
    if (!_variableName.hasMatch(variable)) {
      throw FormatException('Variable no válida: $variable');
    }
    final xRange = settings.remove(variable.toLowerCase());
    final yRange = settings.remove('y');
    if (settings.isNotEmpty) {
      throw FormatException(
        'Opción desconocida: ${settings.keys.first} '
        '(usa $variable:, y: o var:)',
      );
    }
    if (exprs.isEmpty) {
      throw const FormatException('Escribe al menos una expresión');
    }
    if (exprs.length > maxExpressions) {
      throw const FormatException(
        'Como máximo $maxExpressions expresiones por gráfica',
      );
    }

    final (xMin, xMax) = xRange == null
        ? (-10.0, 10.0)
        : _parseRange(variable, xRange);
    final (yMin, yMax) = yRange == null
        ? (null, null)
        : _parseRange('y', yRange);
    return PlotSpec(
      exprs: List.unmodifiable(exprs),
      variable: variable,
      xMin: xMin,
      xMax: xMax,
      yMin: yMin,
      yMax: yMax,
    );
  }

  final List<String> exprs;
  final String variable;
  final double xMin;
  final double xMax;
  final double? yMin;
  final double? yMax;

  static final _setting = RegExp(r'^([A-Za-z][A-Za-z0-9]*)\s*:\s*(.*)$');
  static final _variableName = RegExp(r'^[A-Za-z][A-Za-z0-9]{0,19}$');
  static final _bound = RegExp(
    r'^(-?(?:\d+(?:\.\d*)?|\.\d+)?)\s*\*?\s*(pi|π)?$',
  );

  static (double, double) _parseRange(String name, String text) {
    final parts = text.split(RegExp(r'\s*[,;]\s*|\s+'));
    if (parts.length != 2) {
      throw FormatException('Rango de $name: usa «$name: mínimo, máximo»');
    }
    final low = _parseBound(name, parts[0]);
    final high = _parseBound(name, parts[1]);
    if (low >= high) {
      throw FormatException('Rango de $name: el mínimo debe ser menor');
    }
    return (low, high);
  }

  /// Número, con `pi` opcional: `2`, `-1.5`, `pi`, `-2pi`, `0.5*pi`.
  static double _parseBound(String name, String text) {
    final match = _bound.firstMatch(text);
    if (match == null || text.isEmpty) {
      throw FormatException('Rango de $name: «$text» no es un número');
    }
    final number = match[1]!;
    final isPi = match[2] != null;
    final coefficient = switch (number) {
      '' => 1.0,
      '-' => -1.0,
      _ => double.parse(number),
    };
    if (!isPi && (number.isEmpty || number == '-')) {
      throw FormatException('Rango de $name: «$text» no es un número');
    }
    return isPi ? coefficient * math.pi : coefficient;
  }

  /// Cuerpo de `POST /plot`.
  Map<String, Object> toRequestJson({
    required bool dark,
    required int width,
    required int height,
    required double scale,
  }) => {
    'exprs': exprs,
    'var': variable,
    'x_min': xMin,
    'x_max': xMax,
    if (yMin != null && yMax != null) ...{'y_min': yMin!, 'y_max': yMax!},
    'theme': dark ? 'dark' : 'light',
    'width': width,
    'height': height,
    'scale': scale,
  };

  @override
  bool operator ==(Object other) =>
      other is PlotSpec &&
      listEquals(other.exprs, exprs) &&
      other.variable == variable &&
      other.xMin == xMin &&
      other.xMax == xMax &&
      other.yMin == yMin &&
      other.yMax == yMax;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(exprs), variable, xMin, xMax, yMin, yMax);
}
