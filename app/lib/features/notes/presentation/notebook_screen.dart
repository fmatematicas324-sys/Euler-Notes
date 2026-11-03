import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/state_views.dart';
import '../domain/note.dart';
import 'note_editor_screen.dart';
import 'notes_controller.dart';

/// Pantalla de un cuaderno: lista de notas y creación de notas nuevas.
class NotebookScreen extends ConsumerWidget {
  const NotebookScreen({
    super.key,
    required this.notebookId,
    required this.title,
  });

  final int notebookId;
  final String title;

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref,
    int noteId,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => NoteEditorScreen(noteId: noteId)),
    );
    // El título o la fecha pueden haber cambiado en el editor.
    ref.invalidate(notesControllerProvider(notebookId));
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final noteTitle = await showTextInputDialog(
      context,
      title: 'Nueva nota',
      label: 'Título',
      confirmLabel: 'Crear',
    );
    if (noteTitle == null || !context.mounted) return;
    Note? created;
    final ok = await runGuarded(context, () async {
      created = await ref
          .read(notesControllerProvider(notebookId).notifier)
          .create(noteTitle);
    });
    if (ok && created != null && context.mounted) {
      await _openEditor(context, ref, created!.id);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    NoteSummary note,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Eliminar nota',
      message:
          'Se eliminará «${note.title}». Esta acción no se puede deshacer.',
    );
    if (!confirmed || !context.mounted) return;
    await runGuarded(
      context,
      () => ref
          .read(notesControllerProvider(notebookId).notifier)
          .delete(note.id),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(notesControllerProvider(notebookId));
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.note_add),
        label: const Text('Nueva nota'),
      ),
      body: notes.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(notesControllerProvider(notebookId)),
        ),
        data: (items) => items.isEmpty
            ? const EmptyView(
                icon: Icons.description_outlined,
                title: 'Este cuaderno está vacío',
                message: 'Crea tu primera nota con «Nueva nota».',
              )
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final note = items[index];
                  return ListTile(
                    leading: const Icon(Icons.description),
                    title: Text(note.title),
                    subtitle: Text(
                      'Actualizada ${formatDateTime(note.updatedAt)}',
                    ),
                    onTap: () => _openEditor(context, ref, note.id),
                    trailing: IconButton(
                      tooltip: 'Eliminar nota',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delete(context, ref, note),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
