import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/paper_style.dart';

/// Píxeles lógicos por milímetro (1 px lógico = 1/96 de pulgada).
const double pxPerMm = 96 / 25.4;

/// Fondo de papel detrás de [child] (el texto se dibuja encima).
class PaperBackground extends StatelessWidget {
  const PaperBackground({
    super.key,
    required this.style,
    required this.child,
    this.lineHeight = 24,
    this.topOffset = 16,
  });

  final PaperStyle style;
  final Widget child;

  /// Separación del renglonado: coincide con la altura de línea del texto.
  final double lineHeight;

  /// Posición del primer renglón (el relleno superior del texto).
  final double topOffset;

  @override
  Widget build(BuildContext context) {
    if (style == PaperStyle.blank) return child;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return CustomPaint(
      painter: PaperPainter(
        style: style,
        dark: dark,
        lineHeight: lineHeight,
        topOffset: topOffset,
      ),
      child: child,
    );
  }
}

class PaperPainter extends CustomPainter {
  const PaperPainter({
    required this.style,
    required this.dark,
    this.lineHeight = 24,
    this.topOffset = 16,
  });

  final PaperStyle style;
  final bool dark;
  final double lineHeight;
  final double topOffset;

  /// Tinta: azul grisácea; el milimetrado usa el naranja clásico.
  Color _ink(double alpha) {
    final base = style == PaperStyle.grid
        ? (dark ? const Color(0xFFFFA94D) : const Color(0xFFE8590C))
        : (dark ? const Color(0xFF91A7FF) : const Color(0xFF4263EB));
    return base.withValues(alpha: alpha * (dark ? 0.8 : 1));
  }

  Paint _line(double alpha, [double width = 1]) => Paint()
    ..color = _ink(alpha)
    ..strokeWidth = width;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    switch (style) {
      case PaperStyle.blank:
        return;
      case PaperStyle.ruled:
        _ruled(canvas, size);
      case PaperStyle.grid:
        _millimetre(canvas, size);
      case PaperStyle.dots:
        _dots(canvas, size);
      case PaperStyle.semilog:
        _semilog(canvas, size);
    }
  }

  void _ruled(Canvas canvas, Size size) {
    final paint = _line(0.22);
    // Cada renglón bajo la línea de texto correspondiente.
    for (var y = topOffset + lineHeight - 2; y < size.height; y += lineHeight) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    // Margen.
    canvas.drawLine(
      const Offset(8, 0),
      Offset(8, size.height),
      Paint()
        ..color = const Color(0xFFE03131).withValues(alpha: dark ? 0.35 : 0.3)
        ..strokeWidth = 1,
    );
  }

  void _millimetre(Canvas canvas, Size size) {
    final minor = _line(0.1, 0.5);
    final middle = _line(0.2, 0.8);
    final major = _line(0.35, 1.1);
    final columns = (size.width / pxPerMm).ceil();
    final rows = (size.height / pxPerMm).ceil();
    for (var i = 0; i <= columns; i++) {
      final x = i * pxPerMm;
      final paint = i % 10 == 0 ? major : (i % 5 == 0 ? middle : minor);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var j = 0; j <= rows; j++) {
      final y = j * pxPerMm;
      final paint = j % 10 == 0 ? major : (j % 5 == 0 ? middle : minor);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _dots(Canvas canvas, Size size) {
    const spacing = 5 * pxPerMm; // 5 mm, como un dot grid habitual
    final paint = Paint()..color = _ink(0.35);
    for (var y = spacing; y < size.height; y += spacing) {
      for (var x = spacing; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), 1.1, paint);
      }
    }
  }

  /// Eje vertical logarítmico (décadas de 1 a 10) y horizontal lineal.
  void _semilog(Canvas canvas, Size size) {
    const decade = 60 * pxPerMm; // 6 cm por década
    final minor = _line(0.14, 0.6);
    final major = _line(0.38, 1.1);
    for (var x = 0.0, i = 0; x <= size.width; x += 2 * pxPerMm, i++) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        i % 5 == 0 ? major : minor,
      );
    }
    for (var base = 0.0; base < size.height; base += decade) {
      for (var m = 1; m <= 9; m++) {
        // m = 1 es el borde inferior de la década; 10 sería el superior.
        final y = base + decade * (1 - math.log(m) / math.ln10);
        canvas.drawLine(
          Offset(0, y),
          Offset(size.width, y),
          m == 1 ? major : minor,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant PaperPainter oldDelegate) =>
      oldDelegate.style != style ||
      oldDelegate.dark != dark ||
      oldDelegate.lineHeight != lineHeight ||
      oldDelegate.topOffset != topOffset;
}

/// Muestra pequeña de un papel para menús y selectores.
class PaperSwatch extends StatelessWidget {
  const PaperSwatch({super.key, required this.style, this.size = 28});

  final PaperStyle style;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      clipBehavior: Clip.antiAlias,
      child: PaperBackground(
        style: style,
        lineHeight: 7,
        topOffset: 0,
        child: const SizedBox.expand(),
      ),
    );
  }
}
