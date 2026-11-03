import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../domain/note.dart';

class NotesRepository {
  NotesRepository(this._api);

  final ApiClient _api;

  Future<List<NoteSummary>> list(int notebookId) async {
    final body =
        await _api.get('/notebooks/$notebookId/notes') as List<dynamic>;
    return [
      for (final item in body)
        NoteSummary.fromJson(item as Map<String, dynamic>),
    ];
  }

  Future<Note> create(int notebookId, String title) async => Note.fromJson(
    await _api.post('/notebooks/$notebookId/notes', {'title': title})
        as Map<String, dynamic>,
  );

  Future<Note> get(int id) async =>
      Note.fromJson(await _api.get('/notes/$id') as Map<String, dynamic>);

  Future<Note> update(int id, {String? title, String? content}) async =>
      Note.fromJson(
        await _api.put('/notes/$id', {'title': ?title, 'content': ?content})
            as Map<String, dynamic>,
      );

  Future<void> delete(int id) => _api.delete('/notes/$id');
}

final notesRepositoryProvider = Provider<NotesRepository>(
  (ref) => NotesRepository(ref.watch(apiClientProvider)),
);
