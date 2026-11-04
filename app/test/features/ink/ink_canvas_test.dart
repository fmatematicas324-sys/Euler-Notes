import 'dart:ui';

import 'package:euler_notes/features/ink/domain/ink_document.dart';
import 'package:euler_notes/features/ink/domain/stroke.dart';
import 'package:euler_notes/features/ink/presentation/ink_canvas.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InkDocument document;
  var stylusDetected = 0;
  var pointer = 100;

  setUp(() {
    document = InkDocument();
    stylusDetected = 0;
  });

  /// Lienzo de 1000×700 unidades mostrado a 500×350 px (escala 0,5).
  Future<void> pump(
    WidgetTester tester, {
    InkMode mode = InkMode.pen,
    bool fingerDraws = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 500,
            child: InkCanvas(
              document: document,
              canvasSize: const Size(1000, 700),
              mode: mode,
              color: const Color(0xFF1C64D9),
              strokeWidth: 3,
              fingerDraws: fingerDraws,
              onStylusDetected: () => stylusDetected++,
            ),
          ),
        ),
      ),
    );
  }

  /// Trazo de (10,10) a (60,60) px con [kind] y presiones crecientes.
  Future<void> drawStroke(
    WidgetTester tester,
    PointerDeviceKind kind, {
    List<double> pressures = const [0.2, 0.5, 0.9],
  }) async {
    final id = pointer++;
    final origin = tester.getTopLeft(find.byType(InkCanvas));
    final positions = [
      for (var i = 0; i < pressures.length; i++)
        origin +
            Offset(
              10 + 50.0 * i / (pressures.length - 1),
              10 + 50.0 * i / (pressures.length - 1),
            ),
    ];
    tester.binding.handlePointerEvent(
      PointerDownEvent(
        pointer: id,
        kind: kind,
        position: positions.first,
        pressure: pressures.first,
        pressureMin: 0,
        pressureMax: 1,
      ),
    );
    for (var i = 1; i < positions.length; i++) {
      tester.binding.handlePointerEvent(
        PointerMoveEvent(
          pointer: id,
          kind: kind,
          position: positions[i],
          pressure: pressures[i],
          pressureMin: 0,
          pressureMax: 1,
        ),
      );
    }
    tester.binding.handlePointerEvent(
      PointerUpEvent(pointer: id, kind: kind, position: positions.last),
    );
    await tester.pump();
  }

  testWidgets('el lápiz dibuja con su presión en unidades del lienzo', (
    tester,
  ) async {
    await pump(tester);
    await drawStroke(tester, PointerDeviceKind.stylus);

    final stroke = document.strokes.single;
    expect(stroke.points.map((p) => p.pressure), [0.2, 0.5, 0.9]);
    // Escala 0,5: 10 px → 20 unidades; 60 px → 120 unidades.
    expect(stroke.points.first.offset, const Offset(20, 20));
    expect(stroke.points.last.offset, const Offset(120, 120));
    expect(stroke.color, const Color(0xFF1C64D9));
    expect(stylusDetected, 1);
  });

  testWidgets('el resaltador guarda su herramienta', (tester) async {
    await pump(tester, mode: InkMode.highlighter);
    await drawStroke(tester, PointerDeviceKind.mouse);
    expect(document.strokes.single.tool, InkTool.highlighter);
    expect(document.strokes.single.points.first.pressure, 0.5);
  });

  testWidgets('el dedo dibuja solo si está permitido', (tester) async {
    await pump(tester, fingerDraws: false);
    await drawStroke(tester, PointerDeviceKind.touch);
    expect(document.strokes, isEmpty);

    await pump(tester);
    await drawStroke(tester, PointerDeviceKind.touch);
    expect(document.strokes, hasLength(1));
  });

  testWidgets('rechazo de palma: el dedo no dibuja con el lápiz apoyado', (
    tester,
  ) async {
    await pump(tester);
    final origin = tester.getTopLeft(find.byType(InkCanvas));
    tester.binding.handlePointerEvent(
      PointerDownEvent(
        pointer: 1,
        kind: PointerDeviceKind.stylus,
        position: origin + const Offset(100, 100),
        pressure: 0.6,
        pressureMin: 0,
        pressureMax: 1,
      ),
    );
    // La palma toca mientras el lápiz está apoyado.
    tester.binding.handlePointerEvent(
      PointerDownEvent(
        pointer: 2,
        kind: PointerDeviceKind.touch,
        position: origin + const Offset(300, 200),
      ),
    );
    tester.binding
      ..handlePointerEvent(
        PointerMoveEvent(
          pointer: 2,
          kind: PointerDeviceKind.touch,
          position: origin + const Offset(320, 220),
        ),
      )
      ..handlePointerEvent(
        PointerUpEvent(
          pointer: 2,
          kind: PointerDeviceKind.touch,
          position: origin + const Offset(320, 220),
        ),
      )
      ..handlePointerEvent(
        PointerUpEvent(
          pointer: 1,
          kind: PointerDeviceKind.stylus,
          position: origin + const Offset(100, 100),
        ),
      );
    await tester.pump();

    expect(document.strokes, hasLength(1));
    expect(
      document.strokes.single.points.single.offset,
      const Offset(200, 200),
    );
  });

  testWidgets('el extremo borrador del lápiz borra trazos', (tester) async {
    await pump(tester);
    await drawStroke(tester, PointerDeviceKind.stylus);
    expect(document.strokes, hasLength(1));

    await drawStroke(tester, PointerDeviceKind.invertedStylus);
    expect(document.strokes, isEmpty);
  });

  testWidgets('modo borrador con el ratón', (tester) async {
    await pump(tester);
    await drawStroke(tester, PointerDeviceKind.mouse);
    await pump(tester, mode: InkMode.eraser);
    await drawStroke(tester, PointerDeviceKind.mouse);
    expect(document.strokes, isEmpty);
    document.undo();
    expect(document.strokes, hasLength(1));
  });
}
