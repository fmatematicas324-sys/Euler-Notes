import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../../../core/local_db/local_database_provider.dart';
import '../../../core/server_settings.dart';
import '../domain/note.dart';
import '../domain/paper_style.dart';
import 'local_notes_repository.dart';

/// Notas. Dos implementaciones: el servidor ([ApiNotesRepository]) o la copia
/// de la tablet ([LocalNotesRepository], modo sin conexión).
abstract interface class NotesRepository {
  Future<List<NoteSummary>> list(String notebookId);

  Future<Note> create(String notebookId, String title);

  Future<Note> get(String id);

  Future<Note> update(
    String id, {
    String? title,
    String? content,
    PaperStyle? paper,
  });

  Future<void> delete(String id);
}

class ApiNotesRepository implements NotesRepository {
  ApiNotesRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<NoteSummary>> list(String notebookId) async {
    final body =
        await _api.get('/notebooks/$notebookId/notes') as List<dynamic>;
    return [
      for (final item in body)
        NoteSummary.fromJson(item as Map<String, dynamic>),
    ];
  }

  @override
  Future<Note> create(String notebookId, String title) async => Note.fromJson(
    await _api.post('/notebooks/$notebookId/notes', {'title': title})
        as Map<String, dynamic>,
  );

  @override
  Future<Note> get(String id) async =>
      Note.fromJson(await _api.get('/notes/$id') as Map<String, dynamic>);

  @override
  Future<Note> update(
    String id, {
    String? title,
    String? content,
    PaperStyle? paper,
  }) async => Note.fromJson(
    await _api.put('/notes/$id', {
      'title': ?title,
      'content': ?content,
      'paper': ?paper?.id,
    }) as Map<String, dynamic>,
  );

  @override
  Future<void> delete(String id) => _api.delete('/notes/$id');
}

final notesRepositoryProvider = Provider<NotesRepository>(
  (ref) => ref.watch(offlineModeProvider)
      ? LocalNotesRepository(ref.watch(localDatabaseProvider))
      : ApiNotesRepository(ref.watch(apiClientProvider)),
);
