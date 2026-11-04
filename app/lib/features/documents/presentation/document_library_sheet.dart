import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/state_views.dart';
import '../data/documents_repository.dart';
import '../domain/library_document.dart';
import 'documents_controller.dart';

/// Biblioteca de PDF: importar, abrir y eliminar. [onOpen] recibe el documento
/// elegido (la hoja se cierra antes).
class DocumentLibrarySheet extends ConsumerStatefulWidget {
  const DocumentLibrarySheet({super.key, required this.onOpen});

  final ValueChanged<LibraryDocument> onOpen;

  @override
  ConsumerState<DocumentLibrarySheet> createState() =>
      _DocumentLibrarySheetState();
}

class _DocumentLibrarySheetState extends ConsumerState<DocumentLibrarySheet> {
  bool _uploading = false;

  void _open(LibraryDocument document) {
    Navigator.of(context).pop();
    widget.onOpen(document);
  }

  Future<void> _import() async {
    final picked = await ref.read(pdfPickerProvider)();
    if (picked == null || !mounted) return;
    setState(() => _uploading = true);
    LibraryDocument? document;
    final ok = await runGuarded(context, () async {
      document = await ref
          .read(documentsControllerProvider.notifier)
          .upload(picked);
    });
    if (!mounted) return;
    setState(() => _uploading = false);
    if (ok && document != null) _open(document!);
  }

  Future<void> _delete(LibraryDocument document) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Eliminar PDF',
      message:
          'Se eliminará «${document.filename}» de la biblioteca. '
          'Lo que ya insertaste en tus notas no cambia.',
    );
    if (!confirmed || !mounted) return;
    await runGuarded(
      context,
      () => ref.read(documentsControllerProvider.notifier).delete(document.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final documents = ref.watch(documentsControllerProvider);
    final theme = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Biblioteca de PDF',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _uploading ? null : _import,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Importar PDF'),
                  ),
                ],
              ),
            ),
            if (_uploading) const LinearProgressIndicator(),
            Flexible(
              child: documents.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(32),
                  child: LoadingView(),
                ),
                error: (error, _) => ErrorView(
                  error: error,
                  onRetry: () => ref.invalidate(documentsControllerProvider),
                ),
                data: (items) => items.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: EmptyView(
                          icon: Icons.picture_as_pdf_outlined,
                          title: 'Aún no hay PDF',
                          message:
                              'Importa apuntes, artículos o enunciados para '
                              'leerlos y extraer texto y fórmulas.',
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final document = items[index];
                          return ListTile(
                            leading: const Icon(Icons.picture_as_pdf),
                            title: Text(document.filename),
                            subtitle: Text(
                              '${document.pages} '
                              '${document.pages == 1 ? 'página' : 'páginas'} · '
                              '${formatBytes(document.size)}',
                            ),
                            onTap: () => _open(document),
                            trailing: IconButton(
                              tooltip: 'Eliminar PDF',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(document),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
