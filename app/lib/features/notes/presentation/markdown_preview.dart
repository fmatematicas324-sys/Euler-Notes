import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../core/widgets/math_formula.dart';
import '../../ink/presentation/ink_preview.dart';
import '../../plot/domain/diagram_spec.dart';
import '../../plot/domain/figure_spec.dart';
import '../../plot/domain/plot_spec.dart';
import '../../plot/presentation/figure_view.dart';

/// Vista previa de Markdown con fórmulas LaTeX nativas:
/// - `$...$` en línea (sin espacio junto a los `$`, para no confundir precios).
/// - `$$...$$` en una línea propia (o varias) se muestra como bloque centrado.
/// - `$$...$$` dentro de un párrafo se muestra en estilo display, en línea.
/// - Un bloque ` ```plot ` se muestra como gráfica (ver [PlotSpec.parse]) y uno
///   ` ```diagram ` como diagrama científico (ver [DiagramSpec.parse]).
class MarkdownPreview extends StatelessWidget {
  const MarkdownPreview({super.key, required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    if (data.trim().isEmpty) {
      return Center(
        child: Text(
          'La vista previa aparecerá aquí',
          style: TextStyle(color: Theme.of(context).hintColor),
        ),
      );
    }
    return Markdown(
      data: data,
      padding: const EdgeInsets.all(16),
      extensionSet: md.ExtensionSet.gitHubFlavored,
      blockSyntaxes: [FigureBlockSyntax(), MathBlockSyntax()],
      inlineSyntaxes: [MathInlineSyntax()],
      builders: {
        MathInlineSyntax.tag: _InlineMathBuilder(),
        MathBlockSyntax.tag: _BlockMathBuilder(),
        FigureBlockSyntax.tag: _FigureBuilder(),
      },
    );
  }
}

/// Bloque ` ```plot `, ` ```diagram ` o ` ```ink ` hasta la siguiente ` ``` `.
class FigureBlockSyntax extends md.BlockSyntax {
  static const tag = 'figure';
  static final _start = RegExp(r'^\s*```\s*(plot|diagram|diagrama|ink)\s*$');
  static final _end = RegExp(r'^\s*```\s*$');

  @override
  RegExp get pattern => _start;

  @override
  md.Node parse(md.BlockParser parser) {
    final language = _start.firstMatch(parser.current.content)![1]!;
    parser.advance();
    final lines = <String>[];
    while (!parser.isDone) {
      final line = parser.current.content;
      parser.advance();
      if (_end.hasMatch(line)) break;
      lines.add(line);
    }
    return md.Element.empty(tag)
      ..attributes['language'] = language
      ..attributes['source'] = lines.join('\n');
  }
}

/// `$$ ... $$` como bloque: empieza en una línea que comienza por `$$` y
/// termina en la primera línea que contiene el `$$` de cierre.
class MathBlockSyntax extends md.BlockSyntax {
  static const tag = 'math_block';
  static final _start = RegExp(r'^\s*\$\$');

  @override
  RegExp get pattern => _start;

  @override
  md.Node parse(md.BlockParser parser) {
    final first = parser.current.content.trimLeft().substring(2);
    parser.advance();

    final buffer = StringBuffer();
    final sameLineEnd = first.indexOf(r'$$');
    if (sameLineEnd >= 0) {
      buffer.write(first.substring(0, sameLineEnd));
    } else {
      buffer.writeln(first);
      while (!parser.isDone) {
        final line = parser.current.content;
        parser.advance();
        final end = line.indexOf(r'$$');
        if (end >= 0) {
          buffer.write(line.substring(0, end));
          break;
        }
        buffer.writeln(line);
      }
    }
    return md.Element.empty(tag)..attributes['tex'] = buffer.toString().trim();
  }
}

class MathInlineSyntax extends md.InlineSyntax {
  MathInlineSyntax()
    : super(
        r'\$\$([^$]+?)\$\$|\$([^\s$](?:[^$\n]*?[^\s$])?)\$',
        startCharacter: 0x24, // '$'
      );

  static const tag = 'math';

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final display = match[1] != null;
    parser.addNode(
      md.Element.empty(tag)
        ..attributes['tex'] = (match[1] ?? match[2]!).trim()
        ..attributes['display'] = '$display',
    );
    return true;
  }
}

class _InlineMathBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    return Text.rich(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: MathFormula(
          tex: element.attributes['tex'] ?? '',
          display: element.attributes['display'] == 'true',
          style: parentStyle,
        ),
      ),
    );
  }
}

class _BlockMathBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final base = Theme.of(context).textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: MathFormula(
            tex: element.attributes['tex'] ?? '',
            display: true,
            style: base?.copyWith(fontSize: (base.fontSize ?? 16) * 1.3),
          ),
        ),
      ),
    );
  }
}

class _FigureBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final source = element.attributes['source'] ?? '';
    if (element.attributes['language'] == 'ink') {
      // Número del servidor o UUID de la copia local (Etapa 2).
      final id = RegExp(r'id\s*:\s*([0-9A-Za-z-]+)').firstMatch(source)?[1];
      if (id == null) {
        return Text(
          'Dibujo no válido: falta «id: …»',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: InkPreview(drawingId: id),
      );
    }
    final isPlot = element.attributes['language'] == 'plot';
    try {
      final FigureSpec spec = isPlot
          ? PlotSpec.parse(source)
          : DiagramSpec.parse(source);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: FigureView(spec: spec, height: isPlot ? 300 : 340),
      );
    } on FormatException catch (error) {
      final colors = Theme.of(context).colorScheme;
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: colors.error),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '${isPlot ? 'Gráfica no válida' : 'Diagrama no válido'}: '
          '${error.message}',
          style: TextStyle(color: colors.error),
        ),
      );
    }
  }
}
