import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/widgets/backend_status_icon.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/state_views.dart';
import '../../notes/presentation/notebook_screen.dart';
import '../domain/notebook.dart';
import 'notebooks_controller.dart';

/// Pantalla principal: gestión de cuadernos.
class NotebooksScreen extends ConsumerWidget {
  const NotebooksScreen({super.key});

  NotebooksController _controller(WidgetRef ref) =>
      ref.read(notebooksControllerProvider.notifier);

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final title = await showTextInputDialog(
      context,
      title: 'Nuevo cuaderno',
      label: 'Título',
      confirmLabel: 'Crear',
    );
    if (title == null || !context.mounted) return;
    await runGuarded(context, () => _controller(ref).create(title));
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    Notebook notebook,
  ) async {
    final title = await showTextInputDialog(
      context,
      title: 'Renombrar cuaderno',
      label: 'Título',
      initialValue: notebook.title,
      confirmLabel: 'Guardar',
    );
    if (title == null || title == notebook.title || !context.mounted) return;
    await runGuarded(
      context,
      () => _controller(ref).rename(notebook.id, title),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Notebook notebook,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Eliminar cuaderno',
      message:
          'Se eliminará «${notebook.title}» y todas sus notas. '
          'Esta acción no se puede deshacer.',
    );
    if (!confirmed || !context.mounted) return;
    await runGuarded(context, () => _controller(ref).delete(notebook.id));
  }

  void _open(BuildContext context, Notebook notebook) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            NotebookScreen(notebookId: notebook.id, title: notebook.title),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notebooks = ref.watch(notebooksControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cuaderno Científico'),
        actions: [
          BackendStatusIcon(
            onRetry: () => ref.invalidate(notebooksControllerProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo cuaderno'),
      ),
      body: notebooks.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(notebooksControllerProvider),
        ),
        data: (items) => items.isEmpty
            ? const EmptyView(
                icon: Icons.menu_book_outlined,
                title: 'Aún no tienes cuadernos',
                message: 'Crea uno con «Nuevo cuaderno» para empezar.',
              )
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final notebook = items[index];
                  return ListTile(
                    leading: const Icon(Icons.menu_book),
                    title: Text(notebook.title),
                    subtitle: Text(
                      'Actualizado ${formatDateTime(notebook.updatedAt)}',
                    ),
                    onTap: () => _open(context, notebook),
                    trailing: PopupMenuButton<_NotebookAction>(
                      tooltip: 'Opciones',
                      onSelected: (action) => switch (action) {
                        _NotebookAction.rename => _rename(
                          context,
                          ref,
                          notebook,
                        ),
                        _NotebookAction.delete => _delete(
                          context,
                          ref,
                          notebook,
                        ),
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: _NotebookAction.rename,
                          child: ListTile(
                            leading: Icon(Icons.edit),
                            title: Text('Renombrar'),
                          ),
                        ),
                        PopupMenuItem(
                          value: _NotebookAction.delete,
                          child: ListTile(
                            leading: Icon(Icons.delete_outline),
                            title: Text('Eliminar'),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

enum _NotebookAction { rename, delete }
