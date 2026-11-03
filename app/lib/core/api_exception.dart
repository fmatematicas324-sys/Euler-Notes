/// Error devuelto por el backend (`{"error": {"code", "message"}}`) o de red.
class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.statusCode,
  });

  /// Código estable del backend (`not_found`, `invalid_expression`, ...) o
  /// `network_error` / `bad_response` si el fallo ocurre antes.
  final String code;
  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiException($code, $statusCode): $message';
}

/// Mensaje legible para mostrar al usuario a partir de cualquier error.
String errorMessage(Object error) => switch (error) {
  ApiException(code: 'network_error') =>
    'No se pudo conectar con el backend. ¿Está arrancado?',
  ApiException(:final message) => message,
  _ => 'Error inesperado: $error',
};
