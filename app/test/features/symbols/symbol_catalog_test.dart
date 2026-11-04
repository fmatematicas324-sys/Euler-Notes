import 'package:euler_notes/features/symbols/domain/latex_symbol.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final symbols = [for (final c in symbolCatalog) ...c.symbols];

  test('el catálogo tiene categorías y nombres únicos', () {
    expect(
      symbolCatalog.map((c) => c.name),
      containsAll(['Cálculo', 'Vectores', 'Matrices']),
    );
    final names = symbols.map((s) => s.name).toList();
    expect(names.toSet().length, names.length);
  });

  for (final symbol in symbols) {
    test('flutter_math_fork interpreta «${symbol.name}»', () {
      expect(Math.tex(symbol.label).parseError, isNull, reason: symbol.label);
      // Lo que se inserta, con algo escrito en la posición del cursor.
      final inserted = symbol.snippet.replaceAll(LatexSymbol.caret, 'x');
      expect(Math.tex(inserted).parseError, isNull, reason: inserted);
    });
  }
}
