import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/notebook_cover.dart';

/// Ilustración vectorial de la portada de un cuaderno. Ocupa todo el espacio
/// disponible; el motivo se dibuja en la parte superior (la inferior queda
/// para la etiqueta con el título).
class CoverArt extends StatelessWidget {
  const CoverArt({super.key, required this.cover});

  final NotebookCover cover;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: CoverPainter(cover), child: const SizedBox.expand());
}

class CoverPainter extends CustomPainter {
  const CoverPainter(this.cover);

  final NotebookCover cover;

  @override
  void paint(Canvas canvas, Size size) {
    final (top, bottom) = _gradients[cover]!;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [top, bottom],
        ).createShader(Offset.zero & size),
    );
    final art = _Art(canvas, size);
    switch (cover) {
      case NotebookCover.classic:
        art.classic();
      case NotebookCover.physics:
        art.physics();
      case NotebookCover.calculus:
        art.calculus();
      case NotebookCover.astronomy:
        art.astronomy();
      case NotebookCover.chemistry:
        art.chemistry();
      case NotebookCover.einstein:
        art.einstein();
      case NotebookCover.curie:
        art.curie();
      case NotebookCover.sagan:
        art.sagan();
    }
  }

  @override
  bool shouldRepaint(covariant CoverPainter oldDelegate) =>
      oldDelegate.cover != cover;

  static const _gradients = {
    NotebookCover.classic: (Color(0xFF1F2A44), Color(0xFF3B4A6B)),
    NotebookCover.physics: (Color(0xFF0B3D91), Color(0xFF1B8A9A)),
    NotebookCover.calculus: (Color(0xFFE8590C), Color(0xFFC2255C)),
    NotebookCover.astronomy: (Color(0xFF0B0B2B), Color(0xFF2B1055)),
    NotebookCover.chemistry: (Color(0xFF087F5B), Color(0xFF1098AD)),
    NotebookCover.einstein: (Color(0xFF2E4A3B), Color(0xFF1F3328)),
    NotebookCover.curie: (Color(0xFF0A1F1C), Color(0xFF14403A)),
    NotebookCover.sagan: (Color(0xFF05070F), Color(0xFF13224A)),
  };
}

/// Motivos de cada portada, en coordenadas relativas al tamaño.
class _Art {
  _Art(this.canvas, Size size)
    : w = size.width,
      h = size.height,
      s = size.shortestSide;

  final Canvas canvas;
  final double w;
  final double h;
  final double s;

  Paint _stroke(Color color, double width) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..color = color;

  Paint _fill(Color color) => Paint()..color = color;

  void _text(
    String text,
    Offset center,
    double fontSize,
    Color color, {
    FontWeight weight = FontWeight.w500,
    FontStyle style = FontStyle.normal,
    TextAlign align = TextAlign.center,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          color: color,
          fontWeight: weight,
          fontStyle: style,
          height: 1.1,
        ),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: w);
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  void _stars(int count, int seed, {double maxY = 1}) {
    final random = math.Random(seed);
    for (var i = 0; i < count; i++) {
      final center = Offset(
        random.nextDouble() * w,
        random.nextDouble() * h * maxY,
      );
      final radius = (0.4 + random.nextDouble() * 1.1) * s / 200;
      canvas.drawCircle(
        center,
        radius,
        _fill(Colors.white.withValues(alpha: 0.35 + random.nextDouble() * 0.6)),
      );
    }
  }

  // --- Portadas ----------------------------------------------------------------

  void classic() {
    final line = _stroke(Colors.white.withValues(alpha: 0.04), 1);
    for (var x = -h; x < w; x += 6) {
      canvas.drawLine(Offset(x, 0), Offset(x + h, h), line);
    }
    const gold = Color(0xFFC9A55A);
    canvas.drawRect(
      Rect.fromLTRB(s * 0.08, s * 0.08, w - s * 0.08, h - s * 0.08),
      _stroke(gold.withValues(alpha: 0.7), 1.5),
    );
    final center = Offset(w / 2, h * 0.3);
    canvas.drawCircle(center, s * 0.17, _stroke(gold, 2));
    canvas.drawCircle(
      center,
      s * 0.13,
      _stroke(gold.withValues(alpha: 0.6), 1),
    );
    _text('Σ', center, s * 0.17, gold, weight: FontWeight.w300);
  }

  void physics() {
    final center = Offset(w / 2, h * 0.32);
    final orbit = _stroke(Colors.white.withValues(alpha: 0.85), s * 0.012);
    for (var i = 0; i < 3; i++) {
      final angle = i * math.pi / 3;
      canvas
        ..save()
        ..translate(center.dx, center.dy)
        ..rotate(angle);
      final ellipse = Rect.fromCenter(
        center: Offset.zero,
        width: s * 0.72,
        height: s * 0.24,
      );
      canvas.drawOval(ellipse, orbit);
      final electron = Offset(
        math.cos(1.1 + i) * ellipse.width / 2,
        math.sin(1.1 + i) * ellipse.height / 2,
      );
      canvas
        ..drawCircle(electron, s * 0.022, _fill(const Color(0xFF9BE7FF)))
        ..restore();
    }
    canvas.drawCircle(center, s * 0.06, _fill(const Color(0xFFFFD166)));
    _text(
      'ħ',
      Offset(w * 0.18, h * 0.08),
      s * 0.1,
      Colors.white.withValues(alpha: 0.6),
      style: FontStyle.italic,
    );
  }

  void calculus() {
    _text(
      '∫',
      Offset(w * 0.3, h * 0.29),
      s * 0.62,
      Colors.white.withValues(alpha: 0.92),
      weight: FontWeight.w300,
    );
    final curve = Path();
    for (var i = 0; i <= 60; i++) {
      final t = i / 60;
      final x = w * (0.45 + 0.5 * t);
      final y = h * (0.33 - 0.12 * math.sin(t * 2 * math.pi));
      i == 0 ? curve.moveTo(x, y) : curve.lineTo(x, y);
    }
    canvas.drawPath(curve, _stroke(Colors.white, s * 0.014));
    // Tangente en el máximo de la curva (t = 0.25).
    final peak = Offset(w * 0.575, h * 0.21);
    canvas
      ..drawLine(
        peak - Offset(s * 0.16, 0),
        peak + Offset(s * 0.16, 0),
        _stroke(const Color(0xFFFFE066), s * 0.01),
      )
      ..drawCircle(peak, s * 0.02, _fill(const Color(0xFFFFE066)));
    _text(
      'dx',
      Offset(w * 0.78, h * 0.52),
      s * 0.11,
      Colors.white.withValues(alpha: 0.85),
      style: FontStyle.italic,
    );
  }

  void astronomy() {
    _stars(70, 42);
    final planet = Offset(w * 0.6, h * 0.3);
    final radius = s * 0.17;
    canvas.drawCircle(
      planet,
      radius,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.4, -0.4),
          colors: [Color(0xFFF4C28A), Color(0xFFE76F51)],
        ).createShader(Rect.fromCircle(center: planet, radius: radius)),
    );
    canvas
      ..save()
      ..translate(planet.dx, planet.dy)
      ..rotate(-0.35)
      ..drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: radius * 3.2,
          height: radius * 0.9,
        ),
        _stroke(const Color(0xFFFFE8D6).withValues(alpha: 0.9), s * 0.016),
      )
      ..restore();
    // Luna creciente.
    final moon = Offset(w * 0.22, h * 0.14);
    final crescent = Path.combine(
      PathOperation.difference,
      Path()..addOval(Rect.fromCircle(center: moon, radius: s * 0.07)),
      Path()..addOval(
        Rect.fromCircle(
          center: moon + Offset(s * 0.035, -s * 0.02),
          radius: s * 0.065,
        ),
      ),
    );
    canvas.drawPath(crescent, _fill(const Color(0xFFF1F3F5)));
  }

  void chemistry() {
    final ring = Offset(w * 0.36, h * 0.24);
    final r = s * 0.19;
    final hexagon = Path();
    for (var i = 0; i < 6; i++) {
      final angle = math.pi / 6 + i * math.pi / 3;
      final point = ring + Offset(math.cos(angle) * r, math.sin(angle) * r);
      i == 0
          ? hexagon.moveTo(point.dx, point.dy)
          : hexagon.lineTo(point.dx, point.dy);
    }
    hexagon.close();
    canvas
      ..drawPath(hexagon, _stroke(Colors.white, s * 0.014))
      ..drawCircle(
        ring,
        r * 0.58,
        _stroke(Colors.white.withValues(alpha: 0.8), s * 0.01),
      );
    // Matraz Erlenmeyer.
    final base = Offset(w * 0.72, h * 0.56);
    final neck = s * 0.06;
    final flask = Path()
      ..moveTo(base.dx - neck / 2, base.dy - s * 0.34)
      ..lineTo(base.dx - neck / 2, base.dy - s * 0.2)
      ..lineTo(base.dx - s * 0.16, base.dy)
      ..lineTo(base.dx + s * 0.16, base.dy)
      ..lineTo(base.dx + neck / 2, base.dy - s * 0.2)
      ..lineTo(base.dx + neck / 2, base.dy - s * 0.34);
    final liquid = Path()
      ..moveTo(base.dx - s * 0.105, base.dy - s * 0.07)
      ..lineTo(base.dx + s * 0.105, base.dy - s * 0.07)
      ..lineTo(base.dx + s * 0.16, base.dy)
      ..lineTo(base.dx - s * 0.16, base.dy)
      ..close();
    canvas
      ..drawPath(liquid, _fill(const Color(0xFFA9E34B).withValues(alpha: 0.85)))
      ..drawPath(flask, _stroke(Colors.white, s * 0.012));
    for (final (dx, dy, radius) in [
      (-0.02, 0.12, 0.014),
      (0.03, 0.18, 0.01),
      (0.0, 0.25, 0.008),
    ]) {
      canvas.drawCircle(
        base + Offset(dx * s, -dy * s - s * 0.02),
        radius * s,
        _stroke(Colors.white.withValues(alpha: 0.8), 1.2),
      );
    }
  }

  void einstein() {
    // Polvo de tiza.
    final random = math.Random(7);
    for (var i = 0; i < 160; i++) {
      canvas.drawCircle(
        Offset(random.nextDouble() * w, random.nextDouble() * h),
        random.nextDouble() * 1.2,
        _fill(Colors.white.withValues(alpha: 0.05)),
      );
    }
    // Espacio-tiempo curvado por una masa.
    final mass = Offset(w / 2, h * 0.38);
    final chalk = _stroke(Colors.white.withValues(alpha: 0.32), 1.1);
    double well(Offset p) {
      final d2 = (p - mass).distanceSquared / (s * s * 0.03);
      return s * 0.09 * math.exp(-d2);
    }

    for (var row = 0; row <= 6; row++) {
      final path = Path();
      for (var i = 0; i <= 40; i++) {
        final p = Offset(w * i / 40, h * (0.24 + row * 0.045));
        final y = p.dy + well(p);
        i == 0 ? path.moveTo(p.dx, y) : path.lineTo(p.dx, y);
      }
      canvas.drawPath(path, chalk);
    }
    for (var col = 0; col <= 8; col++) {
      final path = Path();
      for (var i = 0; i <= 30; i++) {
        final p = Offset(w * col / 8, h * (0.24 + 0.27 * i / 30));
        final y = p.dy + well(p);
        i == 0 ? path.moveTo(p.dx, y) : path.lineTo(p.dx, y);
      }
      canvas.drawPath(path, chalk);
    }
    canvas.drawCircle(
      mass + Offset(0, s * 0.06),
      s * 0.05,
      _fill(const Color(0xFFFFE066)),
    );
    _text(
      'E = mc²',
      Offset(w / 2, h * 0.12),
      s * 0.17,
      Colors.white.withValues(alpha: 0.92),
      style: FontStyle.italic,
    );
    _text(
      'Relatividad · 1905',
      Offset(w / 2, h * 0.6),
      s * 0.06,
      Colors.white.withValues(alpha: 0.75),
    );
  }

  void curie() {
    final glow = Offset(w / 2, h * 0.22);
    canvas.drawCircle(
      glow,
      s * 0.34,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF8CFFB0).withValues(alpha: 0.55),
            const Color(0xFF8CFFB0).withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: glow, radius: s * 0.34)),
    );
    canvas.drawCircle(glow, s * 0.045, _fill(const Color(0xFFD3FFE0)));
    final rays = _stroke(
      const Color(0xFF8CFFB0).withValues(alpha: 0.7),
      s * 0.008,
    );
    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4 + 0.2;
      canvas.drawLine(
        glow + Offset(math.cos(angle), math.sin(angle)) * s * 0.08,
        glow + Offset(math.cos(angle), math.sin(angle)) * s * 0.16,
        rays,
      );
    }
    for (final (x, symbol, number) in [(0.3, 'Po', '84'), (0.7, 'Ra', '88')]) {
      final tile = Rect.fromCenter(
        center: Offset(w * x, h * 0.46),
        width: s * 0.3,
        height: s * 0.3,
      );
      final rounded = RRect.fromRectAndRadius(tile, Radius.circular(s * 0.03));
      canvas
        ..drawRRect(
          rounded,
          _fill(const Color(0xFF8CFFB0).withValues(alpha: 0.1)),
        )
        ..drawRRect(rounded, _stroke(const Color(0xFF8CFFB0), 1.5));
      _text(
        symbol,
        tile.center + Offset(0, s * 0.02),
        s * 0.12,
        const Color(0xFFD3FFE0),
        weight: FontWeight.w700,
      );
      _text(
        number,
        tile.topLeft + Offset(s * 0.06, s * 0.05),
        s * 0.05,
        const Color(0xFF8CFFB0),
      );
    }
    _text(
      'Radiactividad · 1898',
      Offset(w / 2, h * 0.62),
      s * 0.06,
      Colors.white.withValues(alpha: 0.75),
    );
  }

  void sagan() {
    _stars(45, 3);
    // Haces de luz solar dispersada.
    for (final (offset, width, alpha) in [
      (0.0, 0.07, 0.16),
      (0.16, 0.045, 0.11),
      (-0.18, 0.05, 0.09),
    ]) {
      final x0 = w * (0.95 + offset);
      final x1 = w * (0.1 + offset);
      final beam = Path()
        ..moveTo(x0 - w * width, 0)
        ..lineTo(x0 + w * width, 0)
        ..lineTo(x1 + w * width * 1.6, h * 0.62)
        ..lineTo(x1 - w * width * 1.6, h * 0.62)
        ..close();
      canvas.drawPath(
        beam,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              const Color(0xFFFFD8A8).withValues(alpha: alpha),
              const Color(0xFFFFD8A8).withValues(alpha: alpha * 0.3),
            ],
          ).createShader(Rect.fromLTWH(0, 0, w, h * 0.62)),
      );
    }
    final dot = Offset(w * 0.47, h * 0.33);
    canvas
      ..drawCircle(
        dot,
        s * 0.035,
        _fill(const Color(0xFF9AD0FF).withValues(alpha: 0.18)),
      )
      ..drawCircle(
        dot,
        math.max(1.6, s * 0.011),
        _fill(const Color(0xFFB8DEFF)),
      );
    _text(
      'Un punto azul pálido',
      Offset(w / 2, h * 0.6),
      s * 0.06,
      Colors.white.withValues(alpha: 0.78),
      style: FontStyle.italic,
    );
  }
}
