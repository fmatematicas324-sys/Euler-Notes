import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

/// Fórmula LaTeX renderizada de forma nativa. Si el LaTeX es inválido muestra
/// el texto fuente en color de error en lugar de fallar.
class MathFormula extends StatelessWidget {
  const MathFormula({
    super.key,
    required this.tex,
    this.display = false,
    this.style,
  });

  final String tex;
  final bool display;

  /// Solo se usan `fontSize` y `color`: el peso o la familia del texto que
  /// rodea a la fórmula (p. ej. un título en negrita) no deben alterarla.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Math.tex(
      tex,
      mathStyle: display ? MathStyle.display : MathStyle.text,
      textStyle: TextStyle(fontSize: style?.fontSize, color: style?.color),
      onErrorFallback: (error) => Tooltip(
        message: error.message,
        child: Text(
          display ? '\$\$$tex\$\$' : '\$$tex\$',
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}
