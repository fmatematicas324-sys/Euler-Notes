// Genera los iconos de Euler Notes a partir de AppIconPainter
// (geometría = assets/icon/euler_notes.svg).
//
//   cd app && flutter test tool/generate_app_icons_test.dart
//
// Escribe: web/favicon.png, web/icons/*.png, assets/icon/app_icon.png (ventana
// Linux) y, si existe android/, los mipmap de Android (normales y adaptables).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:euler_notes/core/widgets/app_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _androidDensities = {
  'mdpi': 1.0,
  'hdpi': 1.5,
  'xhdpi': 2.0,
  'xxhdpi': 3.0,
  'xxxhdpi': 4.0,
};

List<(String, int, IconLayer)> _targets() => [
  ('web/favicon.png', 32, IconLayer.full),
  ('web/icons/Icon-192.png', 192, IconLayer.full),
  ('web/icons/Icon-512.png', 512, IconLayer.full),
  ('web/icons/Icon-maskable-192.png', 192, IconLayer.maskable),
  ('web/icons/Icon-maskable-512.png', 512, IconLayer.maskable),
  ('assets/icon/app_icon.png', 512, IconLayer.full),
  if (Directory('android/app/src/main/res').existsSync())
    for (final MapEntry(key: density, value: factor)
        in _androidDensities.entries) ...[
      (
        'android/app/src/main/res/mipmap-$density/ic_launcher.png',
        (48 * factor).round(),
        IconLayer.full,
      ),
      (
        'android/app/src/main/res/mipmap-$density/ic_launcher_foreground.png',
        (108 * factor).round(),
        IconLayer.foreground,
      ),
      (
        'android/app/src/main/res/mipmap-$density/ic_launcher_background.png',
        (108 * factor).round(),
        IconLayer.background,
      ),
    ],
];

void main() {
  testWidgets('genera los iconos', (tester) async {
    tester.view.physicalSize = const Size(1024, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final (path, size, layer) in _targets()) {
      final key = GlobalKey();
      await tester.pumpWidget(
        Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox.square(
              dimension: size.toDouble(),
              child: CustomPaint(painter: AppIconPainter(layer: layer)),
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
      File(path)
        ..createSync(recursive: true)
        ..writeAsBytesSync(png!.buffer.asUint8List());
    }
  });
}
