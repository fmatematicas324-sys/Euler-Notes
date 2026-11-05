import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/api_exception.dart';
import '../../../core/local_db/local_database.dart';
import '../../../core/local_db/local_database_provider.dart';
import '../../../core/local_db/uuid_v7.dart';
import '../domain/drawing.dart';
import '../domain/stroke.dart';
import 'drawings_repository.dart';

/// Dibujos en la copia de la tablet (Etapa 2). Los trazos se guardan en el
/// mismo JSON que usa el servidor (`Stroke.toJson`).
class LocalDrawingsRepository implements DrawingsRepository {
  LocalDrawingsRepository(this._db);

  final LocalDatabase _db;

  /// Lienzo por defecto, igual que el servidor (`DrawingCreate`).
  static const defaultWidth = 1000.0;
  static const defaultHeight = 700.0;

  static Drawing _toDomain(DrawingRow row) => Drawing(
    id: row.id,
    noteId: row.noteId,
    width: row.width,
    height: row.height,
    strokes: [
      for (final s in jsonDecode(row.strokes) as List<dynamic>)
        Stroke.fromJson(s as Map<String, dynamic>),
    ],
  );

  Future<DrawingRow> _row(String id) async {
    final row = await (_db.select(
      _db.drawings,
    )..where((d) => d.id.equals(id))).getSingleOrNull();
    if (row == null) {
      throw const ApiException(
        code: 'not_found',
        message: 'El dibujo no existe en la tablet',
        statusCode: 404,
      );
    }
    return row;
  }

  @override
  Future<Drawing> create(String noteId) async {
    final now = nowMillis();
    final id = uuidV7();
    await _db
        .into(_db.drawings)
        .insert(
          DrawingsCompanion.insert(
            id: id,
            noteId: noteId,
            width: defaultWidth,
            height: defaultHeight,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return _toDomain(await _row(id));
  }

  @override
  Future<Drawing> get(String id) async => _toDomain(await _row(id));

  @override
  Future<Drawing> saveStrokes(String id, List<Stroke> strokes) async {
    await _row(id);
    await (_db.update(_db.drawings)..where((d) => d.id.equals(id))).write(
      DrawingsCompanion(
        strokes: Value(jsonEncode([for (final s in strokes) s.toJson()])),
        updatedAt: Value(nowMillis()),
      ),
    );
    return _toDomain(await _row(id));
  }
}
