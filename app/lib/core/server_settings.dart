import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

/// Preferencias del dispositivo. Se inyecta en `main` (puede ser `null` si el
/// almacenamiento no está disponible: se usa entonces la URL por defecto).
final sharedPreferencesProvider = Provider<SharedPreferences?>((ref) => null);

const _serverUrlKey = 'server_url';

/// URL del backend. Por defecto [apiBaseUrl] (`--dart-define=API_BASE_URL`);
/// el usuario puede cambiarla (p. ej. la IP de su PC desde una tablet).
class ServerUrlController extends Notifier<String> {
  @override
  String build() =>
      ref.watch(sharedPreferencesProvider)?.getString(_serverUrlKey) ??
      apiBaseUrl;

  /// Guarda [url] normalizada. Lanza [FormatException] si no es válida.
  Future<void> change(String url) async {
    final normalized = normalizeServerUrl(url);
    await ref
        .read(sharedPreferencesProvider)
        ?.setString(_serverUrlKey, normalized);
    state = normalized;
  }
}

final serverUrlProvider = NotifierProvider<ServerUrlController, String>(
  ServerUrlController.new,
);

/// `192.168.1.20:8000` → `http://192.168.1.20:8000` (sin barra final).
String normalizeServerUrl(String input) {
  var url = input.trim();
  if (url.isEmpty) {
    throw const FormatException('Escribe la dirección del servidor');
  }
  if (!url.contains('://')) url = 'http://$url';
  url = url.replaceAll(RegExp(r'/+$'), '');
  final uri = Uri.tryParse(url);
  if (uri == null ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      !(uri.scheme == 'http' || uri.scheme == 'https')) {
    throw const FormatException(
      'Dirección no válida (ejemplo: http://192.168.1.20:8000)',
    );
  }
  return url;
}
