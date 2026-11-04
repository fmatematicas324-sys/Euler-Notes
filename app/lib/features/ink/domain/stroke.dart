import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

enum InkTool { pen, highlighter }

@immutable
class InkPoint {
  const InkPoint(this.x, this.y, this.pressure);

  final double x;
  final double y;

  /// Presión normalizada (0–1).
  final double pressure;

  Offset get offset => Offset(x, y);
}

/// Trazo en unidades del lienzo (independientes del tamaño de pantalla).
@immutable
class Stroke {
  Stroke({
    required this.tool,
    required this.color,
    required this.width,
    required List<InkPoint> points,
  }) : points = List.unmodifiable(points);

  factory Stroke.fromJson(Map<String, dynamic> json) {
    final flat = (json['points'] as List<dynamic>).cast<num>();
    return Stroke(
      tool: InkTool.values.byName(json['tool'] as String? ?? 'pen'),
      color: parseHexColor(json['color'] as String? ?? '#1B1F24'),
      width: (json['width'] as num? ?? 3).toDouble(),
      points: [
        for (var i = 0; i + 2 < flat.length; i += 3)
          InkPoint(
            flat[i].toDouble(),
            flat[i + 1].toDouble(),
            flat[i + 2].toDouble(),
          ),
      ],
    );
  }

  final InkTool tool;
  final Color color;

  /// Grosor base; el real depende de la presión (ver [widthForPressure]).
  final double width;
  final List<InkPoint> points;

  /// Rectángulo que contiene el trazo (sin contar su grosor).
  late final Rect bounds = points.isEmpty
      ? Rect.zero
      : Rect.fromPoints(
          Offset(
            points.map((p) => p.x).reduce(math.min),
            points.map((p) => p.y).reduce(math.min),
          ),
          Offset(
            points.map((p) => p.x).reduce(math.max),
            points.map((p) => p.y).reduce(math.max),
          ),
        );

  /// Lista plana `[x, y, p, ...]` redondeada (décimas de unidad y centésimas
  /// de presión) para que el JSON sea compacto.
  Map<String, Object> toJson() => {
    'tool': tool.name,
    'color': formatHexColor(color),
    'width': width,
    'points': [
      for (final p in points) ...[
        (p.x * 10).roundToDouble() / 10,
        (p.y * 10).roundToDouble() / 10,
        (p.pressure * 100).roundToDouble() / 100,
      ],
    ],
  };

  /// ¿Pasa el trazo a menos de [radius] de [point]?
  bool hits(Offset point, double radius) {
    final reach = radius + maxWidth / 2;
    if (!bounds.inflate(reach).contains(point)) return false;
    if (points.length == 1) {
      return (points.first.offset - point).distance <= reach;
    }
    for (var i = 1; i < points.length; i++) {
      if (_distanceToSegment(point, points[i - 1].offset, points[i].offset) <=
          reach) {
        return true;
      }
    }
    return false;
  }

  /// Grosor máximo posible del trazo.
  double get maxWidth => tool == InkTool.highlighter
      ? width * highlighterFactor
      : widthForPressure(width, 1);
}

const highlighterFactor = 4.0;

/// Grosor según la presión: 0,35× sin presión, 1× a media presión, 1,65× a
/// fondo. Los dispositivos sin presión usan 0,5 (grosor base).
double widthForPressure(double base, double pressure) =>
    base * (0.35 + 1.3 * pressure.clamp(0.0, 1.0));

double _distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final lengthSquared = ab.distanceSquared;
  if (lengthSquared == 0) return (p - a).distance;
  final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / lengthSquared).clamp(
    0.0,
    1.0,
  );
  return (p - (a + ab * t)).distance;
}

Color parseHexColor(String hex) =>
    Color(int.parse(hex.substring(1), radix: 16) | 0xFF000000);

String formatHexColor(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
