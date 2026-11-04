import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Logotipo de Cuaderno Científico: una página cuadriculada con espiral, una
/// gráfica y un pequeño átomo, sobre un fondo azul. Es también la fuente de los iconos de la app
/// (`tool/generate_app_icons_test.dart`).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: const CustomPaint(painter: AppIconPainter()),
  );
}

class AppIconPainter extends CustomPainter {
  /// [maskable]: fondo a sangre y motivo dentro de la zona segura (80 %),
  /// como piden los iconos adaptables de Android y las PWA.
  const AppIconPainter({this.maskable = false});

  final bool maskable;

  static const _deep = Color(0xFF0B3D91);
  static const _teal = Color(0xFF1B8A9A);
  static const _accent = Color(0xFFF76707);

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final rect = Offset.zero & Size.square(side);
    final background = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [_deep, _teal],
      ).createShader(rect);
    if (maskable) {
      canvas.drawRect(rect, background);
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(side * 0.22)),
        background,
      );
    }

    // El motivo ocupa el 80 % central en la versión adaptable.
    final scale = maskable ? 0.8 : 1.0;
    canvas
      ..save()
      ..translate(side * (1 - scale) / 2, side * (1 - scale) / 2)
      ..scale(scale);
    _motif(canvas, side);
    canvas.restore();
  }

  void _motif(Canvas canvas, double s) {
    // Página.
    final page = RRect.fromRectAndRadius(
      Rect.fromLTRB(s * 0.24, s * 0.17, s * 0.82, s * 0.83),
      Radius.circular(s * 0.05),
    );
    canvas
      ..drawRRect(
        page.shift(Offset(s * 0.015, s * 0.02)),
        Paint()..color = const Color(0x40000000),
      )
      ..drawRRect(page, Paint()..color = const Color(0xFFFFFDF7));

    // Cuadrícula.
    final grid = Paint()
      ..color = _deep.withValues(alpha: 0.12)
      ..strokeWidth = math.max(0.6, s * 0.006);
    canvas
      ..save()
      ..clipRRect(page);
    for (var x = page.left + s * 0.07; x < page.right; x += s * 0.07) {
      canvas.drawLine(Offset(x, page.top), Offset(x, page.bottom), grid);
    }
    for (var y = page.top + s * 0.07; y < page.bottom; y += s * 0.07) {
      canvas.drawLine(Offset(page.left, y), Offset(page.right, y), grid);
    }
    canvas.restore();

    // Espiral.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.022
      ..color = const Color(0xFFDEE2E6);
    for (var i = 0; i < 5; i++) {
      final y = page.top + page.height * (0.14 + i * 0.18);
      canvas
        ..drawCircle(Offset(page.left, y), s * 0.028, ring)
        ..drawCircle(
          Offset(page.left + s * 0.035, y),
          s * 0.012,
          Paint()..color = _deep.withValues(alpha: 0.5),
        );
    }

    // Ejes y curva: una gráfica sobre papel cuadriculado.
    final axis = Paint()
      ..color = _deep.withValues(alpha: 0.75)
      ..strokeWidth = s * 0.018
      ..strokeCap = StrokeCap.round;
    final origin = Offset(page.left + s * 0.12, page.top + page.height * 0.62);
    canvas
      ..drawLine(origin, Offset(page.right - s * 0.05, origin.dy), axis)
      ..drawLine(origin, Offset(origin.dx, page.top + s * 0.08), axis);
    final curve = Path();
    final width = page.right - s * 0.07 - origin.dx;
    for (var i = 0; i <= 48; i++) {
      final t = i / 48;
      final point = Offset(
        origin.dx + width * t,
        origin.dy - s * 0.13 * math.sin(t * 2 * math.pi) - s * 0.06 * t,
      );
      i == 0
          ? curve.moveTo(point.dx, point.dy)
          : curve.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      curve,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.034
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = _accent,
    );

    // Átomo pequeño de dos órbitas con sus electrones, en la esquina.
    final atom = Offset(page.right - s * 0.13, page.top + s * 0.14);
    final orbit = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.014
      ..color = _teal;
    for (final angle in [math.pi / 4, -math.pi / 4]) {
      canvas
        ..save()
        ..translate(atom.dx, atom.dy)
        ..rotate(angle)
        ..drawOval(
          Rect.fromCenter(
            center: Offset.zero,
            width: s * 0.2,
            height: s * 0.075,
          ),
          orbit,
        )
        ..drawCircle(Offset(s * 0.1, 0), s * 0.016, Paint()..color = _deep)
        ..restore();
    }
    canvas.drawCircle(atom, s * 0.022, Paint()..color = _deep);
  }

  @override
  bool shouldRepaint(covariant AppIconPainter oldDelegate) =>
      oldDelegate.maskable != maskable;
}
