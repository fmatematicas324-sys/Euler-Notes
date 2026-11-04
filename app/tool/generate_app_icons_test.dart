// Genera los iconos de la app a partir de AppIconPainter.
//
//   cd app && flutter test tool/generate_app_icons_test.dart
//
// Escribe: web/favicon.png, web/icons/*.png y assets/icon/app_icon.png
// (icono de la ventana en Linux).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cuaderno_cientifico/core/widgets/app_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _targets = [
  ('web/favicon.png', 32, false),
  ('web/icons/Icon-192.png', 192, false),
  ('web/icons/Icon-512.png', 512, false),
  ('web/icons/Icon-maskable-192.png', 192, true),
  ('web/icons/Icon-maskable-512.png', 512, true),
  ('assets/icon/app_icon.png', 512, false),
];

void main() {
  testWidgets('genera los iconos', (tester) async {
    tester.view.physicalSize = const Size(1024, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final (path, size, maskable) in _targets) {
      final key = GlobalKey();
      await tester.pumpWidget(
        Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox.square(
              dimension: size.toDouble(),
              child: CustomPaint(painter: AppIconPainter(maskable: maskable)),
            ),
          ),
        ),
      );
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final png = await tester.runAsync(() async {
        final image = await boundary.toImage();
        return image.toByteData(format: ui.ImageByteFormat.png);
      });
      File(path).writeAsBytesSync(png!.buffer.asUint8List());
    }
  });
}
