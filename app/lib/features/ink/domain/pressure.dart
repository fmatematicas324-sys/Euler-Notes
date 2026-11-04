import 'package:flutter/gestures.dart';

/// Presión normalizada (0–1) de un evento.
///
/// - Con rango del dispositivo (`pressureMin < pressureMax`), se normaliza.
/// - Sin rango: Flutter informa `pressure = 1` cuando el dispositivo no mide
///   presión, que se trata como presión media (0,5). Si informa otro valor
///   en 0–1, se usa tal cual.
/// - El ratón nunca tiene presión real (0,5).
double normalizedPressure(PointerEvent event) {
  if (event.kind == PointerDeviceKind.mouse) return 0.5;
  final min = event.pressureMin;
  final max = event.pressureMax;
  if (max > min) return ((event.pressure - min) / (max - min)).clamp(0.0, 1.0);
  final pressure = event.pressure;
  if (pressure == 1 || pressure <= 0 || pressure > 1) return 0.5;
  return pressure;
}
