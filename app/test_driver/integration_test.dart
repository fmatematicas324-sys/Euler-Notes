// Driver de `flutter drive` para las pruebas de integración en navegador.
// Guarda las capturas (`binding.takeScreenshot`) en $SCREENSHOT_DIR o en
// build/screenshots.
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
  writeResponseOnFailure: true,
  onScreenshot: (name, bytes, [args]) async {
    final directory =
        Platform.environment['SCREENSHOT_DIR'] ?? 'build/screenshots';
    await Directory(directory).create(recursive: true);
    await File('$directory/$name.png').writeAsBytes(bytes);
    return true;
  },
);
