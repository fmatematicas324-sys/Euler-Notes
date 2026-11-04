import 'package:flutter/services.dart';

import 'latex_symbol.dart';

/// Saltos de línea necesarios para que un bloque empiece en línea propia.
String blockPrefixAt(String text, int offset) {
  final before = text.substring(0, offset);
  if (before.isEmpty || before.endsWith('\n\n')) return '';
  return before.endsWith('\n') ? '\n' : '\n\n';
}

/// ¿Está `offset` dentro de una fórmula (`$...$` o `$$...$$`)?
///
/// Aproximación suficiente para el editor: cuenta los delimitadores (sin los
/// `\$` escapados) en todo el texto para `$$` y en el párrafo actual para `$`.
bool isInsideMath(String text, int offset) {
  final before = text.substring(0, offset).replaceAll(r'\$', '');
  if (RegExp(r'\$\$').allMatches(before).length.isOdd) return true;
  final paragraph = before.split(RegExp(r'\n[ \t]*\n')).last;
  return RegExp(r'\$').allMatches(paragraph.replaceAll(r'$$', '')).length.isOdd;
}

/// Inserta `symbol` en la selección de `value`:
/// - la selección se coloca en la marca [LatexSymbol.caret] (o se reemplaza);
/// - fuera de una fórmula se envuelve en `$...$` (o `$$...$$` en línea propia
///   si el símbolo es de bloque, como las matrices);
/// - el cursor queda en la marca, o al final del símbolo.
TextEditingValue insertLatexSymbol(TextEditingValue value, LatexSymbol symbol) {
  final text = value.text;
  final selection = value.selection.isValid
      ? value.selection
      : TextSelection.collapsed(offset: text.length);
  final selected = selection.textInside(text);

  var snippet = symbol.snippet;
  final marker = snippet.indexOf(LatexSymbol.caret);
  final int caret;
  if (marker >= 0) {
    snippet = snippet.replaceFirst(LatexSymbol.caret, selected);
    caret = marker + selected.length;
  } else {
    caret = snippet.length;
  }

  var before = '';
  var after = '';
  if (!isInsideMath(text, selection.start)) {
    if (symbol.display) {
      before = '${blockPrefixAt(text, selection.start)}\$\$';
      after = '\$\$\n';
    } else {
      before = r'$';
      after = r'$';
    }
  }
  final inserted = '$before$snippet$after';
  return TextEditingValue(
    text: text.replaceRange(selection.start, selection.end, inserted),
    selection: TextSelection.collapsed(
      offset: selection.start + before.length + caret,
    ),
  );
}
