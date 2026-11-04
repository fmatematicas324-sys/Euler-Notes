import 'package:euler_notes/features/symbols/domain/latex_insertion.dart';
import 'package:euler_notes/features/symbols/domain/latex_symbol.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

TextEditingValue _at(String text, int offset, [int? end]) => TextEditingValue(
  text: text,
  selection: TextSelection(baseOffset: offset, extentOffset: end ?? offset),
);

/// Texto con `|` en la posición del cursor resultante.
String _show(TextEditingValue value) =>
    value.text.replaceRange(value.selection.start, value.selection.start, '|');

const _nabla = LatexSymbol('Nabla', r'\nabla');
const _vector = LatexSymbol(
  'Vector',
  r'\vec{v}',
  '\\vec{${LatexSymbol.caret}}',
);
const _matrix = LatexSymbol(
  'Matriz',
  r'\begin{pmatrix} a \end{pmatrix}',
  '\\begin{pmatrix} ${LatexSymbol.caret} \\end{pmatrix}',
  true,
);

void main() {
  group('isInsideMath', () {
    for (final (text, expected) in [
      (r'texto $x + |', true),
      (r'texto $x$ y |', false),
      (r'$$\int |', true),
      ('\$\$\n\\frac{a}{b}\n|', true),
      (r'$$a$$ y |', false),
      (r'precio \$5 y |', false),
      ('párrafo con \$x\n\nnuevo |', false),
    ]) {
      test(text.replaceAll('\n', r'\n'), () {
        final offset = text.indexOf('|');
        expect(isInsideMath(text.replaceAll('|', ''), offset), expected);
      });
    }
  });

  test(
    'fuera de una fórmula se envuelve en \$...\$ y se sigue escribiendo dentro',
    () {
      expect(
        _show(insertLatexSymbol(_at('Hola ', 5), _nabla)),
        r'Hola $\nabla|$',
      );
    },
  );

  test('dentro de una fórmula se inserta tal cual', () {
    expect(
      _show(insertLatexSymbol(_at(r'$f = $', 5), _nabla)),
      r'$f = \nabla|$',
    );
  });

  test('el cursor queda en la marca y la selección se coloca ahí', () {
    expect(_show(insertLatexSymbol(_at(r'$$', 1), _vector)), r'$\vec{|}$');
    expect(
      _show(insertLatexSymbol(_at(r'$F + E$', 5, 6), _vector)),
      r'$F + \vec{E|}$',
    );
  });

  test('los símbolos de bloque van en \$\$ en línea propia', () {
    expect(
      _show(insertLatexSymbol(_at('Sea A', 5), _matrix)),
      'Sea A\n\n\$\$\\begin{pmatrix} | \\end{pmatrix}\$\$\n',
    );
  });

  test('selección inválida: se inserta al final', () {
    const value = TextEditingValue(text: 'abc');
    expect(_show(insertLatexSymbol(value, _nabla)), r'abc$\nabla|$');
  });

  test('blockPrefixAt', () {
    expect(blockPrefixAt('', 0), '');
    expect(blockPrefixAt('a\n\n', 3), '');
    expect(blockPrefixAt('a\n', 2), '\n');
    expect(blockPrefixAt('a', 1), '\n\n');
  });
}
