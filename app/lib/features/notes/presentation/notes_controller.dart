import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/notes_repository.dart';
import '../domain/note.dart';

/// Notas de un cuaderno (el argumento de la familia es el id del cuaderno).
class NotesController extends AsyncNotifier<List<NoteSummary>> {
  NotesController(this.notebookId);

  final String notebookId;

  NotesRepository get _repository => ref.read(notesRepositoryProvider);

  @override
  Future<List<NoteSummary>> build() =>
      ref.watch(notesRepositoryProvider).list(notebookId);

  Future<Note> create(String title) async {
    final note = await _repository.create(notebookId, title);
    ref.invalidateSelf();
    return note;
  }

  Future<void> delete(String id) async {
    await _repository.delete(id);
    ref.invalidateSelf();
    await future;
  }
}

final notesControllerProvider = AsyncNotifierProvider.autoDispose
    .family<NotesController, List<NoteSummary>, String>(
      NotesController.new,
      retry: (_, _) => null,
    );
