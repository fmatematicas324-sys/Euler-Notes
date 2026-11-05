/// Error devuelto por el backend (`{"error": {"code", "message"}}`) o de red.
class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.mayHaveCompleted = false,
  });

  /// Código estable del backend (`not_found`, `invalid_expression`, ...) o,
  /// si el fallo ocurre antes de tener respuesta: `network_error` (conexión),
  /// `timeout` (tiempo agotado), `cancelled` (cancelada) o `bad_response`.
  final String code;
  final String message;
  final int? statusCode;

  /// `true` si la petición no era idempotente (crear, subir) y no se sabe si
  /// el servidor llegó a aplicarla. La UI no debe afirmar que no se hizo ni
  /// repetirla automáticamente.
  final bool mayHaveCompleted;

  @override
  String toString() => 'ApiException($code, $statusCode): $message';
}

/// Mensaje legible para mostrar al usuario a partir de cualquier error.
String errorMessage(Object error) => switch (error) {
  ApiException(code: 'network_error', mayHaveCompleted: false) =>
    'No se pudo conectar con el backend. ¿Está arrancado?',
  ApiException(code: 'network_error', mayHaveCompleted: true) =>
    'Se perdió la conexión con el backend. La operación pudo completarse: '
        'comprueba el resultado antes de repetirla.',
  ApiException(:final message) => message,
  _ => 'Error inesperado: $error',
};
