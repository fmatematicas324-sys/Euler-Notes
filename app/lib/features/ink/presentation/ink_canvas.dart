import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../notes/domain/paper_style.dart';
import '../../notes/presentation/paper_background.dart';
import '../domain/ink_document.dart';
import '../domain/pressure.dart';
import '../domain/stroke.dart';
import 'ink_painter.dart';

enum InkMode { pen, highlighter, eraser }

/// Lienzo de escritura a mano con presión.
///
/// - El lápiz y el ratón dibujan con la herramienta elegida; el extremo
///   borrador del lápiz (`invertedStylus`) siempre borra.
/// - El dedo dibuja solo si [fingerDraws]; nunca mientras el lápiz está
///   apoyado o justo después (rechazo de la palma).
/// - Un solo trazo a la vez; los demás punteros se ignoran.
class InkCanvas extends StatefulWidget {
  const InkCanvas({
    super.key,
    required this.document,
    required this.canvasSize,
    required this.mode,
    required this.color,
    required this.strokeWidth,
    this.fingerDraws = true,
    this.paper = PaperStyle.blank,
    this.onStylusDetected,
  });

  final InkDocument document;
  final Size canvasSize;
  final InkMode mode;
  final Color color;
  final double strokeWidth;
  final bool fingerDraws;
  final PaperStyle paper;

  /// Se llama la primera vez que se usa un lápiz.
  final VoidCallback? onStylusDetected;

  /// Radio del borrador en unidades del lienzo.
  static const eraserRadius = 10.0;

  /// Tiempo tras levantar el lápiz durante el que se ignora el dedo.
  static const palmGrace = Duration(milliseconds: 600);

  @override
  State<InkCanvas> createState() => _InkCanvasState();
}

class _InkCanvasState extends State<InkCanvas> {
  final _current = ValueNotifier<Stroke?>(null);
  final _points = <InkPoint>[];
  int? _activePointer;
  bool _erasing = false;
  bool _stylusSeen = false;
  DateTime _lastStylus = DateTime.fromMillisecondsSinceEpoch(0);
  bool _stylusDown = false;

  ui.Picture? _picture;
  int _pictureRevision = -1;
  bool? _pictureDark;
  double _scale = 1;

  @override
  void dispose() {
    _current.dispose();
    _picture?.dispose();
    super.dispose();
  }

  ui.Picture _pictureFor(bool dark) {
    if (_picture == null ||
        _pictureRevision != widget.document.revision ||
        _pictureDark != dark) {
      _picture?.dispose();
      _picture = recordStrokes(widget.document.strokes, dark: dark);
      _pictureRevision = widget.document.revision;
      _pictureDark = dark;
    }
    return _picture!;
  }

  bool _isStylus(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.invertedStylus;

  /// ¿Debe este puntero dibujar o borrar?
  bool _accepts(PointerDownEvent event) {
    if (_activePointer != null) return false;
    switch (event.kind) {
      case PointerDeviceKind.stylus:
      case PointerDeviceKind.invertedStylus:
      case PointerDeviceKind.mouse:
        return true;
      case PointerDeviceKind.touch:
        final palmTime =
            _stylusDown ||
            DateTime.now().difference(_lastStylus) < InkCanvas.palmGrace;
        return widget.fingerDraws && !palmTime;
      case PointerDeviceKind.trackpad:
      case PointerDeviceKind.unknown:
        return false;
    }
  }

  Offset _toCanvas(Offset local) => Offset(
    (local.dx / _scale).clamp(0, widget.canvasSize.width),
    (local.dy / _scale).clamp(0, widget.canvasSize.height),
  );

  void _onDown(PointerDownEvent event) {
    if (_isStylus(event.kind)) {
      _stylusDown = true;
      _lastStylus = DateTime.now();
      if (!_stylusSeen) {
        _stylusSeen = true;
        widget.onStylusDetected?.call();
      }
    }
    if (!_accepts(event)) return;
    _activePointer = event.pointer;
    _erasing =
        event.kind == PointerDeviceKind.invertedStylus ||
        widget.mode == InkMode.eraser;
    final point = _toCanvas(event.localPosition);
    if (_erasing) {
      widget.document.eraseAt(point, InkCanvas.eraserRadius);
      return;
    }
    _points
      ..clear()
      ..add(InkPoint(point.dx, point.dy, normalizedPressure(event)));
    _current.value = _stroke();
  }

  void _onMove(PointerMoveEvent event) {
    if (_isStylus(event.kind)) _lastStylus = DateTime.now();
    if (event.pointer != _activePointer) return;
    final point = _toCanvas(event.localPosition);
    if (_erasing) {
      widget.document.eraseAt(point, InkCanvas.eraserRadius);
      return;
    }
    // Ignora movimientos de menos de media unidad (ruido del sensor).
    if ((point - _points.last.offset).distance < 0.5) return;
    _points.add(InkPoint(point.dx, point.dy, normalizedPressure(event)));
    _current.value = _stroke();
  }

  void _onEnd(PointerEvent event, {required bool cancelled}) {
    if (_isStylus(event.kind)) {
      _stylusDown = false;
      _lastStylus = DateTime.now();
    }
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    if (!_erasing && !cancelled && _points.isNotEmpty) {
      widget.document.add(_stroke());
    }
    _points.clear();
    _current.value = null;
  }

  Stroke _stroke() => Stroke(
    tool: widget.mode == InkMode.highlighter
        ? InkTool.highlighter
        : InkTool.pen,
    color: widget.color,
    width: widget.strokeWidth,
    points: _points,
  );

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final size = widget.canvasSize;
    return AspectRatio(
      aspectRatio: size.width / size.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _scale = constraints.maxWidth / size.width;
          return DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: PaperBackground(
              style: widget.paper,
              topOffset: 0,
              lineHeight: 32 * _scale,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _onDown,
                onPointerMove: _onMove,
                onPointerUp: (e) => _onEnd(e, cancelled: false),
                onPointerCancel: (e) => _onEnd(e, cancelled: true),
                child: ListenableBuilder(
                  listenable: widget.document,
                  builder: (context, _) => RepaintBoundary(
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: InkPainter(
                        canvasSize: size,
                        picture: _pictureFor(dark),
                        dark: dark,
                        current: _current,
                        repaint: _current,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
