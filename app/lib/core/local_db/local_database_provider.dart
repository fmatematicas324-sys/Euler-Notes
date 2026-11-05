import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_database.dart';

/// Nombre de la base local real: la copia de las notas en la tablet.
const localDatabaseName = 'euler_notes';

/// Base local compartida por toda la app (una sola conexión). Solo se abre
/// si algo la necesita: el modo sin conexión o el Laboratorio.
final localDatabaseProvider = Provider<LocalDatabase>((ref) {
  final db = LocalDatabase.open(localDatabaseName);
  ref.onDispose(db.close);
  return db;
});

/// Milisegundos Unix → fecha local.
DateTime fromMillis(int millis) => DateTime.fromMillisecondsSinceEpoch(millis);

/// Ahora, en milisegundos Unix.
int nowMillis() => DateTime.now().millisecondsSinceEpoch;
