import 'dart:math';

/// Identificador UUID versión 7 (RFC 9562): 48 bits de milisegundos Unix y
/// 74 bits aleatorios. Se ordena por fecha de creación y no necesita un
/// contador central, lo que permite sincronizar más adelante (ADR 12).
///
/// Solo usa aritmética exacta en `double` (< 2^53), así que da el mismo
/// resultado en la VM y en Web (donde los operadores de bits son de 32 bits).
String uuidV7({DateTime? now, Random? random}) {
  final rng = random ?? Random.secure();
  final bytes = List<int>.filled(16, 0);
  var millis = (now ?? DateTime.now()).millisecondsSinceEpoch;
  for (var i = 5; i >= 0; i--) {
    bytes[i] = millis % 256;
    millis ~/= 256;
  }
  for (var i = 6; i < 16; i++) {
    bytes[i] = rng.nextInt(256);
  }
  bytes[6] = (bytes[6] & 0x0f) | 0x70; // versión 7
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variante RFC
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Fecha de creación codificada en un UUID v7.
DateTime uuidV7Time(String uuid) {
  final hex = uuid.replaceAll('-', '').substring(0, 12);
  return DateTime.fromMillisecondsSinceEpoch(int.parse(hex, radix: 16));
}
