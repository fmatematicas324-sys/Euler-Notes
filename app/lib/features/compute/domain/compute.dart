/// Operaciones soportadas por `POST /compute`. `name` es el valor de la API.
enum ComputeOp {
  simplify('Simplificar'),
  diff('Derivar'),
  integrate('Integrar'),
  solve('Resolver');

  const ComputeOp(this.label);

  final String label;

  bool get usesVariable => this != ComputeOp.simplify;
}

class ComputeResult {
  const ComputeResult({required this.latex, required this.text});

  factory ComputeResult.fromJson(Map<String, dynamic> json) => ComputeResult(
    latex: json['result_latex'] as String,
    text: json['result_text'] as String,
  );

  final String latex;
  final String text;
}
