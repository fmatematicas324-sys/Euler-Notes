import 'package:drift/drift.dart';

import '../../../core/api_exception.dart';
import '../../../core/local_db/local_database.dart';
import '../../../core/local_db/local_database_provider.dart';
import '../../../core/local_db/uuid_v7.dart';
import '../domain/notebook.dart';
import '../domain/notebook_cover.dart';
import 'notebooks_repository.dart';

/// Cuadernos en la copia de la tablet (Etapa 2). Mismo orden y mismas reglas
/// que el servidor; borrar es un borrado lógico (`deleted_at`) del cuaderno y
/// de sus notas.
class LocalNotebooksRepository implements NotebooksRepository {
  LocalNotebooksRepository(this._db);

  final LocalDatabase _db;

  static Notebook _toDomain(NotebookRow row) => Notebook(
    id: row.id,
    title: row.title,
    cover: NotebookCover.fromId(row.cover),
    createdAt: fromMillis(row.createdAt),
    updatedAt: fromMillis(row.updatedAt),
  );

  Future<NotebookRow> _row(String id) async {
    final row =
        await (_db.select(_db.notebooks)
              ..where((n) => n.id.equals(id) & n.deletedAt.isNull()))
            .getSingleOrNull();
    if (row == null) {
      throw const ApiException(
        code: 'not_found',
        message: 'El cuaderno no existe en la tablet',
        statusCode: 404,
      );
    }
    return row;
  }

  @override
  Future<List<Notebook>> list() async {
    final rows =
        await (_db.select(_db.notebooks)
              ..where((n) => n.deletedAt.isNull())
              ..orderBy([
                (n) => OrderingTerm.desc(n.updatedAt),
                (n) => OrderingTerm.desc(n.id),
              ]))
            .get();
    return rows.map(_toDomain).toList();
  }

  @override
  Future<Notebook> create(
    String title, {
    NotebookCover cover = NotebookCover.classic,
  }) async {
    final now = nowMillis();
    final id = uuidV7();
    await _db
        .into(_db.notebooks)
        .insert(
          NotebooksCompanion.insert(
            id: id,
            title: title,
            cover: Value(cover.id),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return _toDomain(await _row(id));
  }

  @override
  Future<Notebook> update(
    String id, {
    String? title,
    NotebookCover? cover,
  }) async {
    await _row(id);
    await (_db.update(_db.notebooks)..where((n) => n.id.equals(id))).write(
      NotebooksCompanion(
        title: title == null ? const Value.absent() : Value(title),
        cover: cover == null ? const Value.absent() : Value(cover.id),
        updatedAt: Value(nowMillis()),
      ),
    );
    return _toDomain(await _row(id));
  }

  @override
  Future<void> delete(String id) async {
    await _row(id);
    // `updated_at` también cambia: así una importación posterior respeta el
    // borrado (la versión de la tablet es más reciente).
    final now = nowMillis();
    await _db.transaction(() async {
      await (_db.update(_db.notes)..where((n) => n.notebookId.equals(id)))
          .write(NotesCompanion(deletedAt: Value(now), updatedAt: Value(now)));
      await (_db.update(_db.notebooks)..where((n) => n.id.equals(id))).write(
        NotebooksCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
    });
  }
}
