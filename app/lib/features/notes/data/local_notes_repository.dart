import 'package:drift/drift.dart';

import '../../../core/api_exception.dart';
import '../../../core/local_db/local_database.dart';
import '../../../core/local_db/local_database_provider.dart';
import '../../../core/local_db/uuid_v7.dart';
import '../domain/note.dart';
import '../domain/paper_style.dart';
import 'notes_repository.dart';

/// Notas en la copia de la tablet (Etapa 2). Mismo orden que el servidor (la
/// más reciente primero); borrar es un borrado lógico (`deleted_at`).
class LocalNotesRepository implements NotesRepository {
  LocalNotesRepository(this._db);

  final LocalDatabase _db;

  static Note _toDomain(NoteRow row) => Note(
    id: row.id,
    notebookId: row.notebookId,
    title: row.title,
    updatedAt: fromMillis(row.updatedAt),
    content: row.content,
    paper: PaperStyle.fromId(row.paper),
  );

  Future<NoteRow> _row(String id) async {
    final row =
        await (_db.select(_db.notes)
              ..where((n) => n.id.equals(id) & n.deletedAt.isNull()))
            .getSingleOrNull();
    if (row == null) {
      throw const ApiException(
        code: 'not_found',
        message: 'La nota no existe en la tablet',
        statusCode: 404,
      );
    }
    return row;
  }

  @override
  Future<List<NoteSummary>> list(String notebookId) async {
    final rows =
        await (_db.select(_db.notes)
              ..where(
                (n) => n.notebookId.equals(notebookId) & n.deletedAt.isNull(),
              )
              ..orderBy([
                (n) => OrderingTerm.desc(n.updatedAt),
                (n) => OrderingTerm.desc(n.id),
              ]))
            .get();
    return rows.map(_toDomain).toList();
  }

  @override
  Future<Note> create(String notebookId, String title) async {
    final notebook =
        await (_db.select(_db.notebooks)
              ..where((n) => n.id.equals(notebookId) & n.deletedAt.isNull()))
            .getSingleOrNull();
    if (notebook == null) {
      throw const ApiException(
        code: 'not_found',
        message: 'El cuaderno no existe en la tablet',
        statusCode: 404,
      );
    }
    final now = nowMillis();
    final id = uuidV7();
    await _db
        .into(_db.notes)
        .insert(
          NotesCompanion.insert(
            id: id,
            notebookId: notebookId,
            title: title,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return _toDomain(await _row(id));
  }

  @override
  Future<Note> get(String id) async => _toDomain(await _row(id));

  @override
  Future<Note> update(
    String id, {
    String? title,
    String? content,
    PaperStyle? paper,
  }) async {
    await _row(id);
    await (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(
        title: title == null ? const Value.absent() : Value(title),
        content: content == null ? const Value.absent() : Value(content),
        paper: paper == null ? const Value.absent() : Value(paper.id),
        updatedAt: Value(nowMillis()),
      ),
    );
    return _toDomain(await _row(id));
  }

  @override
  Future<void> delete(String id) async {
    await _row(id);
    final now = nowMillis();
    await (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      // `updated_at` también: una importación posterior respeta el borrado.
      NotesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }
}
