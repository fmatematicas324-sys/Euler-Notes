import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/backend_status_icon.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/server_dialog.dart';
import '../../../core/widgets/state_views.dart';
import '../../lab/storage_lab_screen.dart';
import '../../notes/presentation/notebook_screen.dart';
import '../domain/notebook.dart';
import 'notebook_cover_card.dart';
import 'notebook_dialogs.dart';
import 'notebooks_controller.dart';

/// Pantalla principal: estantería de cuadernos con portadas ilustradas.
class NotebooksScreen extends ConsumerWidget {
  const NotebooksScreen({super.key});

  NotebooksController _controller(WidgetRef ref) =>
      ref.read(notebooksControllerProvider.notifier);

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final result = await showNewNotebookDialog(context);
    if (result == null || !context.mounted) return;
    final (title, cover) = result;
    await runGuarded(context, () => _controller(ref).create(title, cover));
  }

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    Notebook notebook,
    NotebookAction action,
  ) async {
    switch (action) {
      case NotebookAction.rename:
        final title = await showTextInputDialog(
          context,
          title: 'Renombrar cuaderno',
          label: 'Título',
          initialValue: notebook.title,
          confirmLabel: 'Guardar',
        );
        if (title == null || title == notebook.title || !context.mounted) {
          return;
        }
        await runGuarded(
          context,
          () => _controller(ref).edit(notebook.id, title: title),
        );
      case NotebookAction.changeCover:
        final cover = await showCoverPickerDialog(context, notebook.cover);
        if (cover == null || cover == notebook.cover || !context.mounted) {
          return;
        }
        await runGuarded(
          context,
          () => _controller(ref).edit(notebook.id, cover: cover),
        );
      case NotebookAction.delete:
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
        leading: const Padding(padding: EdgeInsets.all(12), child: AppLogo()),
        title: const Text('Euler Notes'),
        actions: [
          BackendStatusIcon(
            onRetry: () => ref.invalidate(notebooksControllerProvider),
          ),
          IconButton(
            tooltip: 'Servidor',
            icon: const Icon(Icons.dns_outlined),
            onPressed: () => showServerDialog(context),
          ),
          IconButton(
            tooltip: 'Laboratorio',
            icon: const Icon(Icons.science_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const StorageLabScreen()),
            ),
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
          onConfigureServer: () => showServerDialog(context),
        ),
        data: (items) => items.isEmpty
            ? const EmptyView(
                icon: Icons.menu_book_outlined,
                title: 'Aún no tienes cuadernos',
                message: 'Crea uno con «Nuevo cuaderno» para empezar.',
              )
            : GridView.builder(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 104),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200,
                  mainAxisSpacing: 28,
                  crossAxisSpacing: 28,
                  childAspectRatio: 0.66,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final notebook = items[index];
                  return NotebookCoverCard(
                    key: ValueKey(notebook.id),
                    notebook: notebook,
                    onOpen: () => _open(context, notebook),
                    onAction: (action) =>
                        _onAction(context, ref, notebook, action),
                  );
                },
              ),
      ),
    );
  }
}
