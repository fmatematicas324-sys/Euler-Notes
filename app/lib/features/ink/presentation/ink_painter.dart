import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../domain/stroke.dart';

/// Color con el que se ve un trazo: en tema oscuro la tinta casi negra se
/// muestra clara (como en un cuaderno con el papel invertido).
Color displayColor(Color color, {required bool dark}) {
  if (dark && color.computeLuminance() < 0.08) return const Color(0xFFE9ECEF);
  return color;
}

/// Dibuja un trazo en coordenadas del lienzo.
void paintStroke(Canvas canvas, Stroke stroke, {required bool dark}) {
  final points = stroke.points;
  if (points.isEmpty) return;
  final color = displayColor(stroke.color, dark: dark);

  if (stroke.tool == InkTool.highlighter) {
    // Un único trazado: evita que las uniones se oscurezcan al superponerse.
    final path = Path()..moveTo(points.first.x, points.first.y);
    for (final p in points.skip(1)) {
      path.lineTo(p.x, p.y);
    }
    if (points.length == 1) path.lineTo(points.first.x + 0.1, points.first.y);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = stroke.width * highlighterFactor
        ..color = color.withValues(alpha: 0.35),
    );
    return;
  }

  final paint = Paint()
    ..color = color
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  if (points.length == 1) {
    canvas.drawCircle(
      points.first.offset,
      widthForPressure(stroke.width, points.first.pressure) / 2,
      paint..style = PaintingStyle.fill,
    );
    return;
  }
  // Segmentos con el grosor de la presión media de sus extremos.
  for (var i = 1; i < points.length; i++) {
    final a = points[i - 1];
    final b = points[i];
    canvas.drawLine(
      a.offset,
      b.offset,
      paint
        ..strokeWidth = widthForPressure(
          stroke.width,
          (a.pressure + b.pressure) / 2,
        ),
    );
  }
}

/// Graba los trazos terminados en un `Picture` (se reutiliza en cada frame).
ui.Picture recordStrokes(List<Stroke> strokes, {required bool dark}) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  for (final stroke in strokes) {
    paintStroke(canvas, stroke, dark: dark);
  }
  return recorder.endRecording();
}

/// Pinta un dibujo escalado de [canvasSize] (unidades del lienzo) al tamaño
/// del widget. [picture] son los trazos terminados; [current], el que se está
/// dibujando (puede ser `null`).
class InkPainter extends CustomPainter {
  InkPainter({
    required this.canvasSize,
    required this.picture,
    required this.dark,
    this.current,
    super.repaint,
  });

  final Size canvasSize;
  final ui.Picture picture;
  final bool dark;
  final ValueNotifier<Stroke?>? current;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..clipRect(Offset.zero & size)
      ..scale(size.width / canvasSize.width, size.height / canvasSize.height)
      ..drawPicture(picture);
    final stroke = current?.value;
    if (stroke != null) paintStroke(canvas, stroke, dark: dark);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant InkPainter oldDelegate) =>
      oldDelegate.picture != picture ||
      oldDelegate.dark != dark ||
      oldDelegate.canvasSize != canvasSize;
}
