/// Figura que dibuja el backend: una gráfica (`/plot`) o un diagrama
/// (`/diagram`). El widget que la muestra decide tamaño, tema y densidad.
abstract interface class FigureSpec {
  /// Ruta del backend que genera el PNG.
  String get endpoint;

  /// Descripción accesible de la figura.
  String get description;

  Map<String, Object?> toRequestJson({
    required bool dark,
    required int width,
    required int height,
    required double scale,
  });
}
