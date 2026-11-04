import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'figure_spec.dart';
import 'plot_spec.dart';

/// Diagrama científico de `POST /diagram`, escrito en una nota como bloque
/// ` ```diagram `. La primera línea útil indica el tipo:
///
/// ```diagram
/// tipo: funcion        ← análisis visual de una operación de cálculo
/// f: x^3 - 3x
/// op: derivar          ← simplificar | derivar | integrar | resolver
/// x: -2.5, 2.5         ← rango (opcional); var: t para otra variable
/// ```
///
/// ```diagram
/// tipo: fuerzas        ← diagrama de cuerpo libre
/// Normal: 9.8, 90      ← etiqueta: módulo, ángulo en grados
/// Peso: 9.8, 270
/// resultante: no       ← (opcional) ocultar la resultante
/// ```
///
/// ```diagram
/// tipo: proyectil      ← tiro parabólico
/// v0: 20               ← m/s
/// angulo: 45           ← grados
/// g: 9.81              ← (opcional) m/s²
/// h0: 0                ← (opcional) altura inicial en m
/// ```
///
/// ```diagram
/// tipo: grafo
/// A - B: 4             ← arista con peso opcional
/// B -> C               ← «->» hace el grafo dirigido
/// ```
///
/// Los decimales se escriben con punto (`9.8`); la coma separa valores.
@immutable
class DiagramSpec implements FigureSpec {
  const DiagramSpec._(this.kind, this.params, this.description);

  /// `function`, `forces`, `projectile` o `graph` (valor de la API).
  final String kind;
  final Map<String, Object> params;

  @override
  final String description;

  @override
  String get endpoint => '/diagram';

  @override
  Map<String, Object?> toRequestJson({
    required bool dark,
    required int width,
    required int height,
    required double scale,
  }) => {
    'kind': kind,
    ...params,
    'theme': dark ? 'dark' : 'light',
    'width': width,
    'height': height,
    'scale': scale,
  };

  static const maxForces = 8;
  static const maxEdges = 60;

  /// Operaciones de cálculo: nombre en español o de la API → valor de la API.
  static const operations = {
    'simplificar': 'simplify',
    'derivar': 'diff',
    'integrar': 'integrate',
    'resolver': 'solve',
    'simplify': 'simplify',
    'diff': 'diff',
    'integrate': 'integrate',
    'solve': 'solve',
  };

  static const _kinds = {
    'funcion': 'function',
    'function': 'function',
    'fuerzas': 'forces',
    'forces': 'forces',
    'cuerpo libre': 'forces',
    'proyectil': 'projectile',
    'projectile': 'projectile',
    'tiro parabolico': 'projectile',
    'grafo': 'graph',
    'graph': 'graph',
    'red': 'graph',
  };

  /// Plantillas para insertar desde el editor (título → bloque completo).
  static const templates = {
    'Análisis de función': '```diagram\ntipo: funcion\nf: x^3 - 3x\nop: derivar\nx: -2.5, 2.5\n```',
    'Cuerpo libre': '```diagram\ntipo: fuerzas\nNormal: 9.8, 90\nPeso: 9.8, 270\nF: 5, 0\n```',
    'Tiro parabólico':
        '```diagram\ntipo: proyectil\nv0: 20\nangulo: 45\ng: 9.81\n```',
    'Grafo':
        '```diagram\ntipo: grafo\nA - B: 4\nB - C: 2\nC - A: 5\nC - D: 1\n```',
  };

  /// Bloque `tipo: funcion` que representa una operación de `/compute`.
  /// `op` es el valor de la API (`diff`, `solve`...).
  static String functionBlock({
    required String expr,
    required String op,
    String variable = 'x',
  }) {
    final spanish = operations.entries
        .firstWhere((e) => e.value == op && !operations.containsValue(e.key))
        .key;
    final trig = RegExp(r'\b(sin|cos|tan|cot|sec|csc)\b').hasMatch(expr);
    final lines = [
      '```diagram',
      'tipo: funcion',
      'f: $expr',
      'op: $spanish',
      if (variable != 'x') 'var: $variable',
      '$variable: ${trig ? '-2pi, 2pi' : '-10, 10'}',
      '```',
    ];
    return lines.join('\n');
  }

  /// Interpreta el contenido de un bloque ` ```diagram `. Lanza
  /// [FormatException] con un mensaje para el usuario si no es válido.
  factory DiagramSpec.parse(String source) {
    String? kindText;
    final body = <String>[];
    for (final raw in source.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final kind = _kindLine.firstMatch(line);
      if (kind != null) {
        kindText = kind[1]!.trim();
      } else {
        body.add(line);
      }
    }
    if (kindText == null) {
      throw const FormatException(
        'Indica el tipo: «tipo: funcion», «fuerzas», «proyectil» o «grafo»',
      );
    }
    return switch (_kinds[_normalize(kindText)]) {
      'function' => _function(body),
      'forces' => _forces(body),
      'projectile' => _projectile(body),
      'graph' => _graph(body),
      _ => throw FormatException(
        'Tipo desconocido: «$kindText» (usa funcion, fuerzas, proyectil o grafo)',
      ),
    };
  }

  static final _kindLine = RegExp(r'^tipo\s*:\s*(.+)$', caseSensitive: false);
  static final _setting = RegExp(r'^([^:]+?)\s*:\s*(.*)$');
  static final _variableName = RegExp(r'^[A-Za-z][A-Za-z0-9]{0,19}$');
  static final _label = RegExp(r"^[\p{L}\p{N}_ .()+'\-]{1,24}$", unicode: true);
  static final _edge = RegExp(
    r'^(.+?)\s*(->|--|—| - )\s*(.+?)(?:\s*:\s*(\S+))?$',
  );

  static String _normalize(String text) => text
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .trim();

  /// Líneas `clave: valor` con la clave normalizada.
  static Map<String, String> _settings(List<String> body) {
    final settings = <String, String>{};
    for (final line in body) {
      final match = _setting.firstMatch(line);
      if (match == null) {
        throw FormatException('Línea no válida: «$line» (usa «clave: valor»)');
      }
      settings[_normalize(match[1]!)] = match[2]!.trim();
    }
    return settings;
  }

  static double _number(String name, String text) {
    final value = double.tryParse(text.trim());
    if (value == null || !value.isFinite) {
      throw FormatException(
        '$name: «$text» no es un número (decimales con punto)',
      );
    }
    return value;
  }

  static String _checkLabel(String label) {
    if (!_label.hasMatch(label)) {
      throw FormatException(
        'Nombre no válido: «$label» (letras, números y espacios; máx. 24)',
      );
    }
    return label;
  }

  static void _rejectUnknown(Map<String, String> settings) {
    if (settings.isNotEmpty) {
      throw FormatException('Opción desconocida: ${settings.keys.first}');
    }
  }

  static DiagramSpec _function(List<String> body) {
    final settings = _settings(body);
    final expr = settings.remove('f') ?? settings.remove('expr');
    if (expr == null || expr.isEmpty) {
      throw const FormatException('Falta la función: «f: x^2 - 4»');
    }
    final opText = settings.remove('op') ?? 'derivar';
    final op = operations[_normalize(opText)];
    if (op == null) {
      throw FormatException(
        'Operación desconocida: «$opText» '
        '(simplificar, derivar, integrar o resolver)',
      );
    }
    final variable = settings.remove('var') ?? 'x';
    if (!_variableName.hasMatch(variable)) {
      throw FormatException('Variable no válida: $variable');
    }
    final range = settings.remove(variable.toLowerCase());
    final (xMin, xMax) = range == null
        ? (-10.0, 10.0)
        : PlotSpec.parseRange(variable, range);
    _rejectUnknown(settings);
    return DiagramSpec._('function', {
      'expr': expr,
      'op': op,
      'var': variable,
      'x_min': xMin,
      'x_max': xMax,
    }, 'Diagrama de $expr');
  }

  static DiagramSpec _forces(List<String> body) {
    final forces = <Map<String, Object>>[];
    var showResultant = true;
    for (final line in body) {
      final match = _setting.firstMatch(line);
      if (match == null) {
        throw FormatException(
          'Línea no válida: «$line» (usa «Nombre: módulo, ángulo»)',
        );
      }
      final key = match[1]!.trim();
      final value = match[2]!.trim();
      if (_normalize(key) == 'resultante') {
        showResultant = !['no', 'false', '0'].contains(_normalize(value));
        continue;
      }
      final parts = value.split(RegExp(r'\s*[,;]\s*'));
      if (parts.length != 2) {
        throw FormatException('$key: usa «$key: módulo, ángulo»');
      }
      final magnitude = _number(key, parts[0]);
      if (magnitude <= 0) {
        throw FormatException('$key: el módulo debe ser positivo');
      }
      forces.add({
        'label': _checkLabel(key),
        'magnitude': magnitude,
        'angle': _number(key, parts[1]),
      });
    }
    if (forces.isEmpty) {
      throw const FormatException(
        'Añade al menos una fuerza: «Peso: 9.8, 270»',
      );
    }
    if (forces.length > maxForces) {
      throw const FormatException('Como máximo $maxForces fuerzas');
    }
    return DiagramSpec._('forces', {
      'forces': forces,
      'show_resultant': showResultant,
    }, 'Diagrama de cuerpo libre con ${forces.length} fuerzas');
  }

  static DiagramSpec _projectile(List<String> body) {
    final settings = _settings(body);
    final v0Text = settings.remove('v0');
    final angleText =
        settings.remove('angulo') ??
        settings.remove('angle') ??
        settings.remove('θ');
    if (v0Text == null || angleText == null) {
      throw const FormatException('Indica «v0: 20» y «angulo: 45»');
    }
    final v0 = _number('v0', v0Text);
    final angle = _number('angulo', angleText);
    if (v0 <= 0) throw const FormatException('v0 debe ser positiva');
    if (angle <= 0 || angle > 90) {
      throw const FormatException('El ángulo debe estar entre 0 y 90 grados');
    }
    final g = _number('g', settings.remove('g') ?? '9.81');
    final h0 = _number(
      'h0',
      settings.remove('h0') ?? settings.remove('altura') ?? '0',
    );
    if (g <= 0) throw const FormatException('g debe ser positiva');
    if (h0 < 0) throw const FormatException('h0 no puede ser negativa');
    _rejectUnknown(settings);
    return DiagramSpec._('projectile', {
      'v0': v0,
      'angle': angle,
      'g': g,
      'h0': h0,
    }, 'Tiro parabólico con v0 = $v0 m/s y ángulo $angle°');
  }

  static DiagramSpec _graph(List<String> body) {
    final edges = <Map<String, Object?>>[];
    bool? directed;
    var anyArrow = false;
    for (final line in body) {
      final option = _setting.firstMatch(line);
      if (option != null && _normalize(option[1]!) == 'dirigido') {
        directed = [
          'si',
          'sí',
          'yes',
          'true',
          '1',
        ].contains(_normalize(option[2]!));
        continue;
      }
      final edge = _edge.firstMatch(line);
      if (edge == null) {
        throw FormatException(
          'Arista no válida: «$line» (usa «A - B» o «A -> B»)',
        );
      }
      anyArrow |= edge[2] == '->';
      edges.add({
        'source': _checkLabel(edge[1]!.trim()),
        'target': _checkLabel(edge[3]!.trim()),
        'weight': edge[4] == null ? null : _number('Peso', edge[4]!),
      });
    }
    if (edges.isEmpty) {
      throw const FormatException('Añade al menos una arista: «A - B»');
    }
    if (edges.length > maxEdges) {
      throw const FormatException('Como máximo $maxEdges aristas');
    }
    return DiagramSpec._('graph', {
      'edges': edges,
      'directed': directed ?? anyArrow,
    }, 'Grafo con ${edges.length} aristas');
  }

  String get _identity => jsonEncode({'kind': kind, ...params});

  @override
  bool operator ==(Object other) =>
      other is DiagramSpec && other._identity == _identity;

  @override
  int get hashCode => _identity.hashCode;
}
