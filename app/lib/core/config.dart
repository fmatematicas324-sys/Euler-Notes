/// URL del backend local. Se puede cambiar al compilar:
/// `flutter run --dart-define=API_BASE_URL=http://127.0.0.1:9000`
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8000',
);
