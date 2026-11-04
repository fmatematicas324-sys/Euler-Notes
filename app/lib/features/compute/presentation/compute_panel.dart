import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/widgets/math_formula.dart';
import '../../plot/domain/diagram_spec.dart';
import '../data/compute_repository.dart';
import '../domain/compute.dart';

/// `figureBlock`: bloque ` ```diagram ` con la representación visual, si se pidió.
typedef MathInsertCallback = void Function(
  String latex, {
  required bool display,
  String? figureBlock,
});

/// Panel para enviar una expresión a `/compute` e insertar el resultado.
class ComputePanel extends ConsumerStatefulWidget {
  const ComputePanel({super.key, required this.onInsert});

  final MathInsertCallback onInsert;

  @override
  ConsumerState<ComputePanel> createState() => _ComputePanelState();
}

class _ComputePanelState extends ConsumerState<ComputePanel> {
  final _expr = TextEditingController();
  final _variable = TextEditingController(text: 'x');
  ComputeOp _op = ComputeOp.diff;
  bool _withVisual = true;
  bool _busy = false;
  _Computed? _computed;
  ComputeResult? _result;
  Object? _error;

  @override
  void dispose() {
    _expr.dispose();
    _variable.dispose();
    super.dispose();
  }

  Future<void> _compute() async {
    final expr = _expr.text.trim();
    if (expr.isEmpty || _busy) return;
    final variable = _variable.text.trim();
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await ref
          .read(computeRepositoryProvider)
          .compute(
            expr: expr,
            op: _op,
            variable: variable.isEmpty ? 'x' : variable,
          );
      if (mounted) {
        setState(() {
          _result = result;
          _computed = _Computed(expr, _op, variable.isEmpty ? 'x' : variable);
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _insert(ComputeResult result, {required bool display}) {
    final computed = _computed;
    widget.onInsert(
      result.latex,
      display: display,
      figureBlock: _withVisual && computed != null
          ? DiagramSpec.functionBlock(
              expr: computed.expr,
              op: computed.op.name,
              variable: computed.variable,
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const mono = TextStyle(fontFamily: 'monospace');
    final result = _result;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Cálculo simbólico', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              key: const Key('compute-expr'),
              controller: _expr,
              autofocus: true,
              style: mono,
              decoration: const InputDecoration(
                labelText: 'Expresión',
                hintText: 'sin(x)*x     x^2 = 4',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _compute(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<ComputeOp>(
                    key: const Key('compute-op'),
                    initialValue: _op,
                    decoration: const InputDecoration(
                      labelText: 'Operación',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final op in ComputeOp.values)
                        DropdownMenuItem(value: op, child: Text(op.label)),
                    ],
                    onChanged: (op) => setState(() => _op = op ?? _op),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 110,
                  child: TextField(
                    key: const Key('compute-var'),
                    controller: _variable,
                    enabled: _op.usesVariable,
                    style: mono,
                    decoration: const InputDecoration(
                      labelText: 'Variable',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('compute-run'),
              onPressed: _busy ? null : _compute,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: const Text('Calcular'),
            ),
            SwitchListTile(
              key: const Key('compute-visual'),
              contentPadding: EdgeInsets.zero,
              value: _withVisual,
              onChanged: (value) => setState(() => _withVisual = value),
              title: const Text('Añadir representación visual'),
              subtitle: const Text(
                'Inserta también un diagrama: raíces, extremos, área…',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                errorMessage(_error!),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            if (result != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: MathFormula(
                          tex: result.latex,
                          display: true,
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        result.text,
                        textAlign: TextAlign.center,
                        style: mono.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _insert(result, display: false),
                    icon: const Icon(Icons.short_text),
                    label: const Text('Insertar en línea'),
                  ),
                  FilledButton.icon(
                    onPressed: () => _insert(result, display: true),
                    icon: const Icon(Icons.add),
                    label: const Text('Insertar como bloque'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Lo que se calculó, para construir su representación visual.
class _Computed {
  const _Computed(this.expr, this.op, this.variable);

  final String expr;
  final ComputeOp op;
  final String variable;
}
