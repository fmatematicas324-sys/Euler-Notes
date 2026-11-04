import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../notes/domain/paper_style.dart';
import '../data/drawings_repository.dart';
import 'ink_editor_screen.dart';
import 'ink_painter.dart';

/// Dibujo dentro de la vista previa de una nota. Al tocarlo se abre el editor.
class InkPreview extends ConsumerWidget {
  const InkPreview({
    super.key,
    required this.drawingId,
    this.paper = PaperStyle.blank,
  });

  final int drawingId;
  final PaperStyle paper;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InkEditorScreen(drawingId: drawingId, paper: paper),
      ),
    );
    ref.invalidate(drawingProvider(drawingId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final drawing = ref.watch(drawingProvider(drawingId));
    return drawing.when(
      skipLoadingOnRefresh: true,
      loading: () => const SizedBox(
        height: 160,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Text(
        'No se pudo cargar el dibujo: ${errorMessage(error)}',
        style: TextStyle(color: colors.error),
      ),
      data: (drawing) => Tooltip(
        message: 'Editar dibujo',
        child: InkWell(
          key: Key('ink-preview-$drawingId'),
          onTap: () => _edit(context, ref),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: colors.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: AspectRatio(
              aspectRatio: drawing.width / drawing.height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: InkPainter(
                        canvasSize: Size(drawing.width, drawing.height),
                        picture: recordStrokes(drawing.strokes, dark: dark),
                        dark: dark,
                      ),
                    ),
                  ),
                  if (drawing.strokes.isEmpty)
                    Center(
                      child: Text(
                        'Dibujo vacío · toca para dibujar',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ),
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Icon(
                      Icons.draw_outlined,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
