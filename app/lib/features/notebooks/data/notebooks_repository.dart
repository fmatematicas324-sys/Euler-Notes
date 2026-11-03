import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../domain/notebook.dart';

class NotebooksRepository {
  NotebooksRepository(this._api);

  final ApiClient _api;

  Future<List<Notebook>> list() async {
    final body = await _api.get('/notebooks') as List<dynamic>;
    return [
      for (final item in body) Notebook.fromJson(item as Map<String, dynamic>),
    ];
  }

  Future<Notebook> create(String title) async => Notebook.fromJson(
    await _api.post('/notebooks', {'title': title}) as Map<String, dynamic>,
  );

  Future<Notebook> rename(int id, String title) async => Notebook.fromJson(
    await _api.put('/notebooks/$id', {'title': title}) as Map<String, dynamic>,
  );

  Future<void> delete(int id) => _api.delete('/notebooks/$id');
}

final notebooksRepositoryProvider = Provider<NotebooksRepository>(
  (ref) => NotebooksRepository(ref.watch(apiClientProvider)),
);
