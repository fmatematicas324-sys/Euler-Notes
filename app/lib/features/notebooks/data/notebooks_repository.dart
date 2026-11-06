import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../../../core/local_db/local_database_provider.dart';
import '../../../core/server_settings.dart';
import '../domain/notebook.dart';
import '../domain/notebook_cover.dart';
import 'local_notebooks_repository.dart';

/// Cuadernos. Dos implementaciones: el servidor ([ApiNotebooksRepository]) o
/// la copia de la tablet ([LocalNotebooksRepository], modo sin conexión).
abstract interface class NotebooksRepository {
  Future<List<Notebook>> list();

  Future<Notebook> create(
    String title, {
    NotebookCover cover = NotebookCover.classic,
  });

  Future<Notebook> update(String id, {String? title, NotebookCover? cover});

  Future<void> delete(String id);
}

class ApiNotebooksRepository implements NotebooksRepository {
  ApiNotebooksRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<Notebook>> list() async {
    final body = await _api.get('/notebooks') as List<dynamic>;
    return [
      for (final item in body) Notebook.fromJson(item as Map<String, dynamic>),
    ];
  }

  @override
  Future<Notebook> create(
    String title, {
    NotebookCover cover = NotebookCover.classic,
  }) async => Notebook.fromJson(
    await _api.post('/notebooks', {'title': title, 'cover': cover.id})
        as Map<String, dynamic>,
  );

  @override
  Future<Notebook> update(
    String id, {
    String? title,
    NotebookCover? cover,
  }) async => Notebook.fromJson(
    await _api.put('/notebooks/$id', {'title': ?title, 'cover': ?cover?.id})
        as Map<String, dynamic>,
  );

  @override
  Future<void> delete(String id) => _api.delete('/notebooks/$id');
}

final notebooksRepositoryProvider = Provider<NotebooksRepository>(
  (ref) => ref.watch(offlineModeProvider)
      ? LocalNotebooksRepository(ref.watch(localDatabaseProvider))
      : ApiNotebooksRepository(ref.watch(apiClientProvider)),
);
