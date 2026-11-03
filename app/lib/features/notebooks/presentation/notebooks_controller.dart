import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/notebooks_repository.dart';
import '../domain/notebook.dart';

/// Lista de cuadernos. Tras cada cambio se recarga desde el backend, que es la
/// fuente de verdad (orden por última actualización).
class NotebooksController extends AsyncNotifier<List<Notebook>> {
  NotebooksRepository get _repository => ref.read(notebooksRepositoryProvider);

  @override
  Future<List<Notebook>> build() =>
      ref.watch(notebooksRepositoryProvider).list();

  Future<Notebook> create(String title) async {
    final notebook = await _repository.create(title);
    await _reload();
    return notebook;
  }

  Future<void> rename(int id, String title) async {
    await _repository.rename(id, title);
    await _reload();
  }

  Future<void> delete(int id) async {
    await _repository.delete(id);
    await _reload();
  }

  Future<void> _reload() async {
    ref.invalidateSelf();
    await future;
  }
}

final notebooksControllerProvider =
    AsyncNotifierProvider<NotebooksController, List<Notebook>>(
      NotebooksController.new,
      retry: (_, _) => null,
    );
