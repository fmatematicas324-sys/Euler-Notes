import 'package:flutter/material.dart';

import '../../../core/widgets/math_formula.dart';
import '../domain/latex_symbol.dart';

/// Teclado de símbolos científicos: pestañas por categoría y botones que
/// muestran cada símbolo renderizado.
class SymbolPalette extends StatelessWidget {
  const SymbolPalette({super.key, required this.onSelected});

  final ValueChanged<LatexSymbol> onSelected;

  static const height = 220.0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      child: DefaultTabController(
        length: symbolCatalog.length,
        child: SizedBox(
          height: height,
          child: Column(
            children: [
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  for (final category in symbolCatalog)
                    Tab(text: category.name),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    for (final category in symbolCatalog)
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(8),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final symbol in category.symbols)
                              _SymbolButton(
                                symbol: symbol,
                                onPressed: () => onSelected(symbol),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SymbolButton extends StatelessWidget {
  const _SymbolButton({required this.symbol, required this.onPressed});

  final LatexSymbol symbol;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: symbol.name,
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('symbol-${symbol.name}'),
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: 48,
              maxWidth: symbol.display ? 150 : 180,
              minHeight: 48,
              maxHeight: 56,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Center(
                widthFactor: 1,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: MathFormula(
                    tex: symbol.label,
                    style: TextStyle(fontSize: 18, color: colors.onSurface),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
