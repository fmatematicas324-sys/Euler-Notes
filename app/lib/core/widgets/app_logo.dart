import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Logotipo de Euler Notes: un átomo en órbita sobre la portada minimalista de
/// un cuaderno (lomo y cinta marcapáginas), sobre un fondo azul.
///
/// Geometría idéntica a `assets/icon/euler_notes.svg` (unidades 0–1 del lado).
/// Es la fuente de los iconos (`tool/generate_app_icons_test.dart`).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: const CustomPaint(painter: AppIconPainter()),
  );
}

/// Capa del icono a dibujar.
enum IconLayer {
  /// Icono completo con esquinas redondeadas.
  full,

  /// Fondo a sangre y motivo en la zona segura (PWA «maskable»).
  maskable,

  /// Solo el motivo, transparente (primer plano del icono adaptable Android).
  foreground,

  /// Solo el fondo (fondo del icono adaptable Android).
  background,
}

class AppIconPainter extends CustomPainter {
  const AppIconPainter({this.layer = IconLayer.full});

  final IconLayer layer;

  static const deepBlue = Color(0xFF0B3D91);
  static const teal = Color(0xFF1B8A9A);
  static const accent = Color(0xFFF76707);
  static const paper = Color(0xFFFFFDF7);
  static const spine = Color(0xFFDDE3EA);

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final rect = Offset.zero & Size.square(side);
    final background = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [deepBlue, teal],
      ).createShader(rect);

    switch (layer) {
      case IconLayer.full:
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(side * 0.22)),
          background,
        );
        _motif(canvas, side, 1);
      case IconLayer.maskable:
        canvas.drawRect(rect, background);
        _motif(canvas, side, 0.8);
      case IconLayer.foreground:
        // Zona segura del icono adaptable: 66 de 108 dp.
        _motif(canvas, side, 0.72);
      case IconLayer.background:
        canvas.drawRect(rect, background);
    }
  }

  void _motif(Canvas canvas, double side, double scale) {
    canvas
      ..save()
      ..translate(side * (1 - scale) / 2, side * (1 - scale) / 2)
      ..scale(scale);
    final s = side;
    Offset p(double x, double y) => Offset(x * s, y * s);

    // Portada con sombra.
    final cover = RRect.fromRectAndRadius(
      Rect.fromLTRB(0.27 * s, 0.18 * s, 0.75 * s, 0.82 * s),
      Radius.circular(0.06 * s),
    );
    canvas
      ..drawRRect(
        cover.shift(p(0.014, 0.02)),
        Paint()..color = const Color(0x40000000),
      )
      ..drawRRect(cover, Paint()..color = paper);

    // Lomo.
    canvas
      ..save()
      ..clipRRect(cover)
      ..drawRect(
        Rect.fromLTRB(0.27 * s, 0.18 * s, 0.34 * s, 0.82 * s),
        Paint()..color = spine,
      )
      ..restore();

    // Cinta marcapáginas.
    canvas.drawPath(
      Path()
        ..moveTo(0.63 * s, 0.18 * s)
        ..lineTo(0.68 * s, 0.18 * s)
        ..lineTo(0.68 * s, 0.36 * s)
        ..lineTo(0.655 * s, 0.33 * s)
        ..lineTo(0.63 * s, 0.36 * s)
        ..close(),
      Paint()..color = accent,
    );

    // Átomo: dos órbitas cruzadas, cada una con su electrón.
    final center = p(0.545, 0.53);
    final orbit = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.022 * s
      ..color = deepBlue;
    for (final degrees in [35.0, -35.0]) {
      canvas
        ..save()
        ..translate(center.dx, center.dy)
        ..rotate(degrees * math.pi / 180)
        ..drawOval(
          Rect.fromCenter(
            center: Offset.zero,
            width: 0.34 * s,
            height: 0.13 * s,
          ),
          orbit,
        )
        ..drawCircle(Offset(0.17 * s, 0), 0.022 * s, Paint()..color = teal)
        ..restore();
    }
    canvas
      ..drawCircle(center, 0.04 * s, Paint()..color = accent)
      ..restore();
  }

  @override
  bool shouldRepaint(covariant AppIconPainter oldDelegate) =>
      oldDelegate.layer != layer;
}
