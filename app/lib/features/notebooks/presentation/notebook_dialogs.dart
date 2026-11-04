import 'package:flutter/material.dart';

import '../domain/notebook_cover.dart';
import 'cover_art.dart';

/// Diálogo de cuaderno nuevo: título y portada. Devuelve `null` si se cancela.
Future<(String, NotebookCover)?> showNewNotebookDialog(BuildContext context) =>
    showDialog<(String, NotebookCover)>(
      context: context,
      builder: (_) => const _NewNotebookDialog(),
    );

/// Elige una portada. Devuelve `null` si se cancela.
Future<NotebookCover?> showCoverPickerDialog(
  BuildContext context,
  NotebookCover current,
) => showDialog<NotebookCover>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Portada'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: CoverPicker(
          selected: current,
          onSelected: (cover) => Navigator.of(context).pop(cover),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
    ],
  ),
);

class _NewNotebookDialog extends StatefulWidget {
  const _NewNotebookDialog();

  @override
  State<_NewNotebookDialog> createState() => _NewNotebookDialogState();
}

class _NewNotebookDialogState extends State<_NewNotebookDialog> {
  final _title = TextEditingController();
  NotebookCover _cover = NotebookCover.physics;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _title.text.trim();
    if (title.isNotEmpty) Navigator.of(context).pop((title, _cover));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuevo cuaderno'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _title,
                autofocus: true,
                maxLength: 200,
                decoration: const InputDecoration(labelText: 'Título'),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 8),
              Text('Portada', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              CoverPicker(
                selected: _cover,
                onSelected: (cover) => setState(() => _cover = cover),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ListenableBuilder(
          listenable: _title,
          builder: (context, _) => FilledButton(
            onPressed: _title.text.trim().isEmpty ? null : _submit,
            child: const Text('Crear'),
          ),
        ),
      ],
    );
  }
}

/// Rejilla de miniaturas de portada.
class CoverPicker extends StatelessWidget {
  const CoverPicker({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final NotebookCover selected;
  final ValueChanged<NotebookCover> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final cover in NotebookCover.values)
          Tooltip(
            message: cover.label,
            child: InkWell(
              key: Key('cover-${cover.id}'),
              onTap: () => onSelected(cover),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 72,
                height: 100,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    width: 3,
                    color: cover == selected
                        ? colors.primary
                        : Colors.transparent,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Semantics(
                    selected: cover == selected,
                    label: cover.label,
                    child: CoverArt(cover: cover),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
