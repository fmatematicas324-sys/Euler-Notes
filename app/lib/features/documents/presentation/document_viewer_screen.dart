import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../core/widgets/state_views.dart';
import '../data/documents_repository.dart';
import '../domain/library_document.dart';

/// Construye el visor de PDF. Se sustituye en tests (pdfium no está disponible).
typedef PdfViewerBuilder = Widget Function(
  Uint8List data,
  String name,
  PdfViewerController controller,
  ValueChanged<int> onPageChanged,
);

final pdfViewerBuilderProvider = Provider<PdfViewerBuilder>(
  (ref) =>
      (data, name, controller, onPageChanged) => PdfViewer.data(
        data,
        sourceName: name,
        controller: controller,
        params: PdfViewerParams(
          onPageChanged: (page) {
            if (page != null) onPageChanged(page);
          },
        ),
      ),
);

/// Lector de PDF con el texto de la página actual para insertarlo en la nota:
/// como cita (pestaña «Texto») o como fórmula (pestaña «LaTeX»).
class DocumentViewerScreen extends ConsumerStatefulWidget {
  const DocumentViewerScreen({
    super.key,
    required this.document,
    required this.onInsert,
  });

  final LibraryDocument document;

  /// Recibe el bloque Markdown a insertar en la nota.
  final ValueChanged<String> onInsert;

  static const wideLayoutWidth = 900.0;

  @override
  ConsumerState<DocumentViewerScreen> createState() =>
      _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends ConsumerState<DocumentViewerScreen> {
  final _controller = PdfViewerController();
  late Future<Uint8List> _file;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _file = ref.read(documentsRepositoryProvider).file(widget.document.id);
  }

  void _goTo(int page) {
    final target = page.clamp(1, widget.document.pages);
    setState(() => _page = target);
    if (_controller.isReady) _controller.goToPage(pageNumber: target);
  }

  void _insert(String markdown) {
    widget.onInsert(markdown);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Insertado en la nota')));
  }

  @override
  Widget build(BuildContext context) {
    final viewer = FutureBuilder<Uint8List>(
      future: _file,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorView(
            error: snapshot.error!,
            onRetry: () => setState(() {
              _file = ref
                  .read(documentsRepositoryProvider)
                  .file(widget.document.id);
            }),
          );
        }
        if (!snapshot.hasData) return const LoadingView();
        return ref.watch(pdfViewerBuilderProvider)(
          snapshot.data!,
          widget.document.filename,
          _controller,
          (page) {
            if (page != _page && mounted) setState(() => _page = page);
          },
        );
      },
    );
    final textPanel = _PageTextPanel(
      document: widget.document,
      page: _page,
      onPage: _goTo,
      onInsert: _insert,
    );

    return Scaffold(
      appBar: AppBar(title: Text(widget.document.filename)),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= DocumentViewerScreen.wideLayoutWidth) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: viewer),
                const VerticalDivider(width: 1),
                SizedBox(width: 400, child: textPanel),
              ],
            );
          }
          return DefaultTabController(
            length: 2,
            child: Column(
              children: [
                const TabBar(
                  tabs: [
                    Tab(icon: Icon(Icons.picture_as_pdf), text: 'Documento'),
                    Tab(icon: Icon(Icons.text_snippet), text: 'Extraer'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    physics: const NeverScrollableScrollPhysics(),
                    children: [viewer, textPanel],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PageTextPanel extends ConsumerStatefulWidget {
  const _PageTextPanel({
    required this.document,
    required this.page,
    required this.onPage,
    required this.onInsert,
  });

  final LibraryDocument document;
  final int page;
  final ValueChanged<int> onPage;
  final ValueChanged<String> onInsert;

  @override
  ConsumerState<_PageTextPanel> createState() => _PageTextPanelState();
}

class _PageTextPanelState extends ConsumerState<_PageTextPanel> {
  final _texts = <int, Future<PageText>>{};
  bool _latex = false;
  String _selection = '';

  Future<PageText> _textFor(int page) => _texts[page] ??= ref
      .read(documentsRepositoryProvider)
      .pageText(widget.document.id, page);

  @override
  void didUpdateWidget(covariant _PageTextPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page != widget.page) _selection = '';
  }

  String _quote(String text) {
    final lines = text.trim().split('\n').map((l) => '> $l'.trimRight());
    return '${lines.join('\n')}\n>\n'
        '> — *${widget.document.filename}*, p. ${widget.page}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pages = widget.document.pages;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Página anterior',
                onPressed: widget.page > 1
                    ? () => widget.onPage(widget.page - 1)
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  'Página ${widget.page} de $pages',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: 'Página siguiente',
                onPressed: widget.page < pages
                    ? () => widget.onPage(widget.page + 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('Texto'),
                icon: Icon(Icons.notes),
              ),
              ButtonSegment(
                value: true,
                label: Text('LaTeX'),
                icon: Icon(Icons.functions),
              ),
            ],
            selected: {_latex},
            onSelectionChanged: (value) => setState(() {
              _latex = value.first;
              _selection = '';
            }),
          ),
        ),
        Expanded(
          child: FutureBuilder<PageText>(
            key: ValueKey(widget.page),
            future: _textFor(widget.page),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return ErrorView(
                  error: snapshot.error!,
                  onRetry: () => setState(() => _texts.remove(widget.page)),
                );
              }
              final pageText = snapshot.data;
              if (pageText == null) return const LoadingView();
              final content = _latex ? pageText.latex : pageText.text;
              if (content.trim().isEmpty) {
                return const EmptyView(
                  icon: Icons.image_not_supported_outlined,
                  title: 'Sin texto en esta página',
                  message:
                      'Puede ser una imagen escaneada: el texto no se puede '
                      'extraer sin reconocimiento óptico (OCR).',
                );
              }
              final selected = _selection.trim();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        content,
                        key: const Key('page-text'),
                        style: _latex
                            ? const TextStyle(fontFamily: 'monospace')
                            : null,
                        onSelectionChanged: (selection, _) => setState(() {
                          _selection = selection.textInside(content);
                        }),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: _latex
                        ? FilledButton.icon(
                            onPressed: selected.isEmpty
                                ? null
                                : () => widget.onInsert('\$\$$selected\$\$'),
                            icon: const Icon(Icons.functions),
                            label: Text(
                              selected.isEmpty
                                  ? 'Selecciona una fórmula'
                                  : 'Insertar como fórmula',
                            ),
                          )
                        : FilledButton.icon(
                            onPressed: () => widget.onInsert(
                              _quote(selected.isEmpty ? content : selected),
                            ),
                            icon: const Icon(Icons.format_quote),
                            label: Text(
                              selected.isEmpty
                                  ? 'Insertar página como cita'
                                  : 'Insertar selección como cita',
                            ),
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Text(
                      _latex
                          ? 'Conversión aproximada: revisa la fórmula tras '
                                'insertarla.'
                          : 'Se añade la fuente (archivo y página).',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
