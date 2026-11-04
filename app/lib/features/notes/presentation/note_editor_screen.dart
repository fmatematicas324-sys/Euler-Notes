import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/state_views.dart';
import '../../compute/presentation/compute_panel.dart';
import '../../documents/domain/library_document.dart';
import '../../documents/presentation/document_library_sheet.dart';
import '../../documents/presentation/document_viewer_screen.dart';
import '../../plot/domain/diagram_spec.dart';
import '../../symbols/domain/latex_insertion.dart';
import '../../symbols/domain/latex_symbol.dart';
import '../../symbols/presentation/symbol_palette.dart';
import '../data/notes_repository.dart';
import 'markdown_preview.dart';

enum SaveStatus { saved, pending, saving, failed }

/// Editor de una nota: Markdown + vista previa con LaTeX + panel de cálculo.
/// Guarda automáticamente tras una pausa al escribir, con Ctrl+S y al salir.
class NoteEditorScreen extends ConsumerStatefulWidget {
  const NoteEditorScreen({super.key, required this.noteId});

  final int noteId;

  static const autosaveDelay = Duration(milliseconds: 800);

  /// A partir de este ancho, editor y vista previa se muestran lado a lado.
  static const wideLayoutWidth = 840.0;

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  final _title = TextEditingController();
  final _content = TextEditingController();
  final _contentFocus = FocusNode();
  bool _showSymbols = false;

  bool _loaded = false;
  Object? _loadError;
  SaveStatus _status = SaveStatus.saved;
  Timer? _autosave;
  Future<bool>? _inFlight;
  String _savedTitle = '';
  String _savedContent = '';

  NotesRepository get _repository => ref.read(notesRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _title.addListener(_onChanged);
    _content.addListener(_onChanged);
    _load();
  }

  @override
  void dispose() {
    _autosave?.cancel();
    _title.dispose();
    _content.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loaded = false;
      _loadError = null;
    });
    try {
      final note = await _repository.get(widget.noteId);
      if (!mounted) return;
      _savedTitle = note.title;
      _savedContent = note.content;
      _title.text = note.title;
      _content.text = note.content;
      setState(() => _loaded = true);
    } on Object catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  /// Un título vacío no se guarda: se conserva el último válido.
  String get _effectiveTitle {
    final title = _title.text.trim();
    return title.isEmpty ? _savedTitle : title;
  }

  bool get _isDirty =>
      _effectiveTitle != _savedTitle || _content.text != _savedContent;

  void _setStatus(SaveStatus status) {
    if (mounted && status != _status) setState(() => _status = status);
  }

  void _onChanged() {
    if (!_loaded) return;
    if (!_isDirty) {
      if (_status == SaveStatus.pending) _setStatus(SaveStatus.saved);
      return;
    }
    if (_status != SaveStatus.saving) _setStatus(SaveStatus.pending);
    _autosave?.cancel();
    _autosave = Timer(NoteEditorScreen.autosaveDelay, _save);
  }

  Future<bool> _save() async {
    _autosave?.cancel();
    if (_inFlight != null) await _inFlight;
    if (!mounted || !_loaded) return false;
    if (!_isDirty) {
      _setStatus(SaveStatus.saved);
      return true;
    }

    final title = _effectiveTitle;
    final content = _content.text;
    _setStatus(SaveStatus.saving);
    final request = () async {
      try {
        await _repository.update(widget.noteId, title: title, content: content);
        _savedTitle = title;
        _savedContent = content;
        return true;
      } on Object catch (error) {
        if (mounted) showErrorSnackBar(context, error);
        return false;
      }
    }();
    _inFlight = request;
    final ok = await request;
    _inFlight = null;

    if (!ok) {
      _setStatus(SaveStatus.failed);
    } else if (_isDirty) {
      // Se siguió escribiendo durante el guardado.
      _setStatus(SaveStatus.pending);
      _autosave = Timer(NoteEditorScreen.autosaveDelay, _save);
    } else {
      _setStatus(SaveStatus.saved);
    }
    return ok;
  }

  Future<void> _handlePop() async {
    if (!_loaded) {
      Navigator.of(context).pop();
      return;
    }
    final ok = await _save();
    if (!mounted) return;
    final leave =
        ok ||
        await showConfirmDialog(
          context,
          title: 'No se pudo guardar',
          message: '¿Salir sin guardar los últimos cambios?',
          confirmLabel: 'Salir',
        );
    if (leave && mounted) Navigator.of(context).pop();
  }

  // --- Edición ---------------------------------------------------------------

  TextSelection _selection() {
    final selection = _content.selection;
    return selection.isValid
        ? selection
        : TextSelection.collapsed(offset: _content.text.length);
  }

  void _replaceSelection(String before, String after) {
    final text = _content.text;
    final selection = _selection();
    final selected = selection.textInside(text);
    _content.value = TextEditingValue(
      text: text.replaceRange(
        selection.start,
        selection.end,
        '$before$selected$after',
      ),
      selection: TextSelection.collapsed(
        offset: selection.start + before.length + selected.length,
      ),
    );
  }

  /// Saltos de línea necesarios para que un bloque empiece en línea propia.
  String _blockPrefix() => blockPrefixAt(_content.text, _selection().start);

  void _insertSymbol(LatexSymbol symbol) {
    _content.value = insertLatexSymbol(
      _content.value.copyWith(selection: _selection()),
      symbol,
    );
    _contentFocus.requestFocus();
  }

  void _insertInlineFormula() => _replaceSelection(r'$', r'$');

  void _insertBlockFormula() =>
      _replaceSelection('${_blockPrefix()}\$\$\n', '\n\$\$\n');

  /// Inserta un bloque (plantilla de gráfica o diagrama) en línea propia.
  void _insertBlock(String block) {
    final selection = _selection();
    final text = '${_blockPrefix()}$block\n';
    _content.value = TextEditingValue(
      text: _content.text.replaceRange(selection.start, selection.end, text),
      selection: TextSelection.collapsed(offset: selection.start + text.length),
    );
  }

  void _insertFigure(String? template) {
    if (template != null) {
      _insertBlock(template);
      return;
    }
    // Gráfica de función: usa la selección como expresión, si la hay.
    final selected = _selection().textInside(_content.text).trim();
    final expr = selected.isEmpty || selected.contains('\n')
        ? 'sin(x)'
        : selected;
    _insertBlock('```plot\n$expr\nx: -2pi, 2pi\n```');
  }

  void _insertMath(String latex, {required bool display, String? figureBlock}) {
    if (display) {
      _replaceSelection('${_blockPrefix()}\$\$$latex\$\$\n', '');
    } else {
      _replaceSelection('\$$latex\$', '');
    }
    if (figureBlock != null) _insertBlock(figureBlock);
  }

  Future<void> _openDocuments() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DocumentLibrarySheet(onOpen: _openDocument),
    );
  }

  void _openDocument(LibraryDocument document) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            DocumentViewerScreen(document: document, onInsert: _insertBlock),
      ),
    );
  }

  Future<void> _openCompute() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: ComputePanel(
          onInsert: (latex, {required display, figureBlock}) {
            Navigator.of(sheetContext).pop();
            _insertMath(latex, display: display, figureBlock: figureBlock);
          },
        ),
      ),
    );
  }

  // --- UI --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handlePop();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        },
        child: Scaffold(
          appBar: AppBar(
            title: _loaded
                ? TextField(
                    key: const Key('note-title'),
                    controller: _title,
                    style: Theme.of(context).textTheme.titleLarge,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Título de la nota',
                    ),
                  )
                : const Text('Nota'),
            actions: [
              if (_loaded) ...[
                _SaveStatusLabel(status: _status),
                IconButton(
                  tooltip: 'Guardar (Ctrl+S)',
                  icon: const Icon(Icons.save_outlined),
                  onPressed: _save,
                ),
              ],
            ],
          ),
          body: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loadError != null) {
      return ErrorView(error: _loadError!, onRetry: _load);
    }
    if (!_loaded) return const LoadingView();

    final editor = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EditorToolbar(
          onInlineFormula: _insertInlineFormula,
          onBlockFormula: _insertBlockFormula,
          onFigure: _insertFigure,
          onCompute: _openCompute,
          onDocuments: _openDocuments,
          symbolsVisible: _showSymbols,
          onToggleSymbols: () => setState(() => _showSymbols = !_showSymbols),
        ),
        if (_showSymbols) SymbolPalette(onSelected: _insertSymbol),
        const Divider(height: 1),
        Expanded(
          child: TextField(
            key: const Key('note-content'),
            controller: _content,
            focusNode: _contentFocus,
            expands: true,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(fontFamily: 'monospace', height: 1.4),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(16),
              hintText:
                  'Escribe en Markdown.\n\n'
                  r'Fórmulas en línea: $E = mc^2$'
                  '\n'
                  r'En bloque: $$\int_0^1 x^2\,dx$$'
                  '\n'
                  'Gráficas: un bloque ```plot con sin(x)',
            ),
          ),
        ),
      ],
    );
    final preview = ValueListenableBuilder<TextEditingValue>(
      valueListenable: _content,
      builder: (_, value, _) => MarkdownPreview(data: value.text),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= NoteEditorScreen.wideLayoutWidth) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: editor),
              const VerticalDivider(width: 1),
              Expanded(child: preview),
            ],
          );
        }
        return DefaultTabController(
          length: 2,
          child: Column(
            children: [
              const TabBar(
                tabs: [
                  Tab(icon: Icon(Icons.edit), text: 'Editar'),
                  Tab(icon: Icon(Icons.visibility), text: 'Vista previa'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  physics: const NeverScrollableScrollPhysics(),
                  children: [editor, preview],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EditorToolbar extends StatelessWidget {
  const _EditorToolbar({
    required this.onInlineFormula,
    required this.onBlockFormula,
    required this.onFigure,
    required this.onCompute,
    required this.onDocuments,
    required this.symbolsVisible,
    required this.onToggleSymbols,
  });

  final VoidCallback onInlineFormula;
  final VoidCallback onBlockFormula;

  /// `null`: gráfica de función; si no, la plantilla de diagrama elegida.
  final ValueChanged<String?> onFigure;
  final VoidCallback onCompute;
  final VoidCallback onDocuments;
  final bool symbolsVisible;
  final VoidCallback onToggleSymbols;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Wrap(
        spacing: 4,
        children: [
          TextButton.icon(
            onPressed: onInlineFormula,
            icon: const Icon(Icons.functions),
            label: const Text(r'$ $ Fórmula'),
          ),
          TextButton.icon(
            onPressed: onBlockFormula,
            icon: const Icon(Icons.calculate_outlined),
            label: const Text(r'$$ Bloque'),
          ),
          MenuAnchor(
            menuChildren: [
              MenuItemButton(
                leadingIcon: const Icon(Icons.show_chart),
                onPressed: () => onFigure(null),
                child: const Text('Gráfica de función'),
              ),
              for (final MapEntry(key: name, value: block)
                  in DiagramSpec.templates.entries)
                MenuItemButton(
                  leadingIcon: const Icon(Icons.schema_outlined),
                  onPressed: () => onFigure(block),
                  child: Text(name),
                ),
            ],
            builder: (context, controller, _) => TextButton.icon(
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              icon: const Icon(Icons.show_chart),
              label: const Text('Gráfica'),
            ),
          ),
          TextButton.icon(
            onPressed: onToggleSymbols,
            icon: Icon(
              symbolsVisible
                  ? Icons.keyboard_hide
                  : Icons.keyboard_alt_outlined,
            ),
            label: const Text('Símbolos'),
          ),
          TextButton.icon(
            onPressed: onDocuments,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('PDF'),
          ),
          FilledButton.tonalIcon(
            onPressed: onCompute,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Calcular'),
          ),
        ],
      ),
    );
  }
}

class _SaveStatusLabel extends StatelessWidget {
  const _SaveStatusLabel({required this.status});

  final SaveStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (icon, label, color) = switch (status) {
      SaveStatus.saved => (Icons.cloud_done, 'Guardado', colors.primary),
      SaveStatus.pending => (Icons.edit_note, 'Sin guardar', colors.outline),
      SaveStatus.saving => (Icons.sync, 'Guardando…', colors.outline),
      SaveStatus.failed => (
        Icons.error_outline,
        'Error al guardar',
        colors.error,
      ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color)),
        ],
      ),
    );
  }
}
