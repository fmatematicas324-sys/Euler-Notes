/// URL del backend local. Se puede cambiar al compilar:
/// `flutter run --dart-define=API_BASE_URL=http://127.0.0.1:9000`
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8000',
);

/// Tiempos máximos de espera de las peticiones al backend. Si se superan, la
/// petición falla con `ApiException(code: 'timeout')` en lugar de quedarse
/// esperando (p. ej. con la WiFi caída o el PC apagado).
class ApiTimeouts {
  const ApiTimeouts({
    this.health = const Duration(seconds: 3),
    this.standard = const Duration(seconds: 10),
    this.compute = const Duration(seconds: 15),
    this.render = const Duration(seconds: 30),
    this.download = const Duration(seconds: 60),
    this.upload = const Duration(seconds: 120),
  });

  /// `/health`: debe responder casi al instante.
  final Duration health;

  /// Cuadernos, notas, dibujos y metadatos de documentos.
  final Duration standard;

  /// `/compute` (el backend corta a los 5 s; margen para la red).
  final Duration compute;

  /// `/plot` y `/diagram` (el primer arranque del motor tarda unos segundos).
  final Duration render;

  /// Descarga de un PDF.
  final Duration download;

  /// Subida de un PDF (hasta 30 MB).
  final Duration upload;
}
