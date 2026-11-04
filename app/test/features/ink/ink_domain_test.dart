import 'dart:ui';

import 'package:cuaderno_cientifico/features/ink/domain/ink_document.dart';
import 'package:cuaderno_cientifico/features/ink/domain/pressure.dart';
import 'package:cuaderno_cientifico/features/ink/domain/stroke.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

Stroke _line(double y, {double pressure = 0.5}) => Stroke(
  tool: InkTool.pen,
  color: const Color(0xFF1C64D9),
  width: 3,
  points: [InkPoint(0, y, pressure), InkPoint(100, y, pressure)],
);

void main() {
  test('JSON compacto: redondeo y vuelta', () {
    final stroke = Stroke(
      tool: InkTool.highlighter,
      color: const Color(0xFFE03131),
      width: 2,
      points: const [InkPoint(10.04, 20.06, 0.333), InkPoint(11, 21, 1)],
    );
    final json = stroke.toJson();
    expect(json, {
      'tool': 'highlighter',
      'color': '#E03131',
      'width': 2.0,
      'points': [10.0, 20.1, 0.33, 11.0, 21.0, 1.0],
    });
    final back = Stroke.fromJson(json);
    expect(back.tool, InkTool.highlighter);
    expect(back.color, const Color(0xFFE03131));
    expect(back.points.last.pressure, 1.0);
  });

  test('grosor según la presión', () {
    expect(widthForPressure(4, 0.5), closeTo(4, 1e-9));
    expect(widthForPressure(4, 0), closeTo(1.4, 1e-9));
    expect(widthForPressure(4, 1), closeTo(6.6, 1e-9));
    expect(widthForPressure(4, 7), widthForPressure(4, 1));
  });

  test('presión normalizada según el dispositivo', () {
    expect(
      normalizedPressure(
        const PointerDownEvent(
          kind: PointerDeviceKind.stylus,
          pressure: 3,
          pressureMin: 1,
          pressureMax: 5,
        ),
      ),
      0.5,
    );
    // El ratón no tiene presión real.
    expect(
      normalizedPressure(const PointerDownEvent(kind: PointerDeviceKind.mouse)),
      0.5,
    );
    // Sin rango: el valor por defecto (1) significa «sin presión».
    expect(
      normalizedPressure(const PointerDownEvent(kind: PointerDeviceKind.touch)),
      0.5,
    );
    // Sin rango pero con un valor 0–1: se usa tal cual.
    expect(
      normalizedPressure(
        const PointerDownEvent(kind: PointerDeviceKind.stylus, pressure: 0.3),
      ),
      0.3,
    );
  });

  test('detección de trazo para el borrador', () {
    final stroke = _line(50);
    expect(stroke.hits(const Offset(50, 52), 2), isTrue);
    expect(stroke.hits(const Offset(50, 70), 2), isFalse);
    expect(stroke.hits(const Offset(150, 50), 2), isFalse);
  });

  test('añadir, borrar, limpiar, deshacer y rehacer', () {
    final document = InkDocument([_line(10)]);
    var notified = 0;
    document.addListener(() => notified++);

    document.add(_line(50));
    expect(document.strokes, hasLength(2));
    expect(document.eraseAt(const Offset(30, 50), 3), isTrue);
    expect(document.eraseAt(const Offset(30, 300), 3), isFalse);
    expect(document.strokes.single.points.first.y, 10);

    document.undo(); // deshace el borrado
    expect(document.strokes, hasLength(2));
    document.undo(); // deshace el trazo añadido
    expect(document.strokes, hasLength(1));
    expect(document.canUndo, isFalse);

    document.redo();
    expect(document.strokes.map((s) => s.points.first.y), [10, 50]);

    document.clear();
    expect(document.strokes, isEmpty);
    document.undo();
    expect(document.strokes.map((s) => s.points.first.y), [10, 50]);

    // Un cambio nuevo vacía la pila de rehacer.
    document
      ..undo()
      ..add(_line(90));
    expect(document.canRedo, isFalse);
    expect(notified, greaterThan(6));
    expect(document.revision, notified);
  });
}
