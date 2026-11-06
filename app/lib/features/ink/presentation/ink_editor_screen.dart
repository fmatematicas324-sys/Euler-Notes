import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/state_views.dart';
import '../../notes/domain/paper_style.dart';
import '../data/drawings_repository.dart';
import '../domain/drawing.dart';
import '../domain/ink_document.dart';
import 'ink_canvas.dart';

/// Editor a pantalla completa de un dibujo a mano. Guarda solo tras cada
/// trazo (con una breve espera) y al salir.
class InkEditorScreen extends ConsumerStatefulWidget {
  const InkEditorScreen({
    super.key,
    required this.drawingId,
    this.paper = PaperStyle.blank,
  });

  final String drawingId;
  final PaperStyle paper;

  static const autosaveDelay = Duration(milliseconds: 800);

  /// Colores de tinta: negro (claro en tema oscuro), azul, rojo, verde,
  /// naranja y violeta.
  static const colors = [
    Color(0xFF1B1F24),
    Color(0xFF1C64D9),
    Color(0xFFE03131),
    Color(0xFF2B8A3E),
    Color(0xFFF08C00),
    Color(0xFF9C36B5),
  ];

  /// Grosores base (unidades del lienzo).
  static const widths = {'Fino': 2.0, 'Medio': 3.5, 'Grueso': 6.0};

  @override
  ConsumerState<InkEditorScreen> createState() => _InkEditorScreenState();
}

class _InkEditorScreenState extends ConsumerState<InkEditorScreen> {
  Drawing? _drawing;
  InkDocument? _document;
  Object? _loadError;
  InkMode _mode = InkMode.pen;
  Color _color = InkEditorScreen.colors.first;
  double _width = InkEditorScreen.widths['Medio']!;
  bool _fingerDraws = true;

  int _savedRevision = 0;
  bool _saving = false;
  bool _saveFailed = false;
  Timer? _autosave;

  DrawingsRepository get _repository => ref.read(drawingsRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _autosave?.cancel();
    _document?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final drawing = await _repository.get(widget.drawingId);
      if (!mounted) return;
      final document = InkDocument(drawing.strokes)..addListener(_onChanged);
      setState(() {
        _drawing = drawing;
        _document = document;
        _savedRevision = document.revision;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  bool get _dirty => _document != null && _document!.revision != _savedRevision;

  void _onChanged() {
    setState(() {}); // deshacer/rehacer y estado de guardado
    _autosave?.cancel();
    _autosave = Timer(InkEditorScreen.autosaveDelay, _save);
  }

  Future<bool> _save() async {
    _autosave?.cancel();
    final document = _document;
    if (document == null || !_dirty) return true;
    if (_saving) {
      // Otro guardado en curso: se volverá a intentar al terminar.
      _autosave = Timer(InkEditorScreen.autosaveDelay, _save);
      return false;
    }
    final revision = document.revision;
    setState(() => _saving = true);
    try {
      await _repository.saveStrokes(widget.drawingId, document.strokes);
      _savedRevision = revision;
      _saveFailed = false;
      return true;
    } on Object catch (error) {
      _saveFailed = true;
      if (mounted) showErrorSnackBar(context, error);
      return false;
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        if (_dirty && !_saveFailed) {
          _autosave = Timer(InkEditorScreen.autosaveDelay, _save);
        }
      }
    }
  }

  Future<void> _handlePop() async {
    final ok = await _save();
    if (!mounted) return;
    final leave =
        ok ||
        await showConfirmDialog(
          context,
          title: 'No se pudo guardar',
          message: '¿Salir sin guardar los últimos trazos?',
          confirmLabel: 'Salir',
        );
    if (leave && mounted) Navigator.of(context).pop();
  }

  Future<void> _clear() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Borrar todo',
      message: 'Se borrarán todos los trazos (puedes deshacerlo).',
      confirmLabel: 'Borrar',
    );
    if (confirmed) _document?.clear();
  }

  void _onStylusDetected() {
    if (!_fingerDraws || !mounted) return;
    setState(() => _fingerDraws = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Lápiz detectado: el dedo ya no dibuja (rechazo de palma)',
        ),
      ),
    );
  }

  String get _status => _saveFailed
      ? 'Error al guardar'
      : _saving
      ? 'Guardando…'
      : _dirty
      ? 'Sin guardar'
      : 'Guardado';

  @override
  Widget build(BuildContext context) {
    final document = _document;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handlePop();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () =>
              document?.undo(),
          const SingleActivator(LogicalKeyboardKey.keyY, control: true): () =>
              document?.redo(),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Dibujo'),
              actions: [
                if (document != null) ...[
                  Center(child: Text(_status)),
                  IconButton(
                    tooltip: 'Deshacer (Ctrl+Z)',
                    onPressed: document.canUndo ? document.undo : null,
                    icon: const Icon(Icons.undo),
                  ),
                  IconButton(
                    tooltip: 'Rehacer (Ctrl+Y)',
                    onPressed: document.canRedo ? document.redo : null,
                    icon: const Icon(Icons.redo),
                  ),
                  IconButton(
                    tooltip: 'Borrar todo',
                    onPressed: document.strokes.isEmpty ? null : _clear,
                    icon: const Icon(Icons.delete_sweep_outlined),
                  ),
                ],
              ],
            ),
            body: _body(),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loadError != null) {
      return ErrorView(error: _loadError!, onRetry: _load);
    }
    final drawing = _drawing;
    final document = _document;
    if (drawing == null || document == null) return const LoadingView();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Toolbar(
          mode: _mode,
          color: _color,
          width: _width,
          fingerDraws: _fingerDraws,
          onMode: (mode) => setState(() => _mode = mode),
          onColor: (color) => setState(() {
            _color = color;
            if (_mode == InkMode.eraser) _mode = InkMode.pen;
          }),
          onWidth: (width) => setState(() => _width = width),
          onFingerDraws: (value) => setState(() => _fingerDraws = value),
        ),
        const Divider(height: 1),
        Expanded(
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: InkCanvas(
                  key: const Key('ink-canvas'),
                  document: document,
                  canvasSize: Size(drawing.width, drawing.height),
                  mode: _mode,
                  color: _color,
                  strokeWidth: _width,
                  fingerDraws: _fingerDraws,
                  paper: widget.paper,
                  onStylusDetected: _onStylusDetected,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.mode,
    required this.color,
    required this.width,
    required this.fingerDraws,
    required this.onMode,
    required this.onColor,
    required this.onWidth,
    required this.onFingerDraws,
  });

  final InkMode mode;
  final Color color;
  final double width;
  final bool fingerDraws;
  final ValueChanged<InkMode> onMode;
  final ValueChanged<Color> onColor;
  final ValueChanged<double> onWidth;
  final ValueChanged<bool> onFingerDraws;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<InkMode>(
            segments: const [
              ButtonSegment(
                value: InkMode.pen,
                icon: Icon(Icons.edit),
                label: Text('Lápiz'),
              ),
              ButtonSegment(
                value: InkMode.highlighter,
                icon: Icon(Icons.highlight),
                label: Text('Resaltador'),
              ),
              ButtonSegment(
                value: InkMode.eraser,
                icon: Icon(Icons.auto_fix_normal),
                label: Text('Borrador'),
              ),
            ],
            selected: {mode},
            onSelectionChanged: (value) => onMode(value.first),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final ink in InkEditorScreen.colors)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: InkWell(
                    key: Key('ink-color-${ink.toARGB32().toRadixString(16)}'),
                    customBorder: const CircleBorder(),
                    onTap: () => onColor(ink),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ink,
                        border: Border.all(
                          width: ink == color ? 3 : 1,
                          color: ink == color
                              ? colors.primary
                              : colors.outlineVariant,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          SegmentedButton<double>(
            showSelectedIcon: false,
            segments: [
              for (final MapEntry(key: name, value: value)
                  in InkEditorScreen.widths.entries)
                ButtonSegment(value: value, label: Text(name)),
            ],
            selected: {width},
            onSelectionChanged: (value) => onWidth(value.first),
          ),
          FilterChip(
            avatar: const Icon(Icons.pan_tool_outlined, size: 18),
            label: const Text('Dibujar con el dedo'),
            selected: fingerDraws,
            onSelected: onFingerDraws,
          ),
        ],
      ),
    );
  }
}
