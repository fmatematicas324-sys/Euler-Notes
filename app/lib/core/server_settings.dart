import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

/// Preferencias del dispositivo. Se inyecta en `main` (puede ser `null` si el
/// almacenamiento no está disponible: se usa entonces la URL por defecto).
final sharedPreferencesProvider = Provider<SharedPreferences?>((ref) => null);

const _serverUrlKey = 'server_url';
const _serverTokenKey = 'server_token';

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

/// Token de acceso al backend (`Authorization: Bearer`). Lo escribe el usuario
/// en el diálogo del servidor; nunca se incluye en el código ni en
/// `--dart-define` de producción.
///
/// Se guarda en `shared_preferences`, que **no está cifrado**; ver
/// `docs/SERVER_SECURITY.md` (propuesta de `flutter_secure_storage`).
class ServerTokenController extends Notifier<String> {
  @override
  String build() =>
      ref.watch(sharedPreferencesProvider)?.getString(_serverTokenKey) ?? '';

  Future<void> change(String token) async {
    final trimmed = token.trim();
    final preferences = ref.read(sharedPreferencesProvider);
    if (trimmed.isEmpty) {
      await preferences?.remove(_serverTokenKey);
    } else {
      await preferences?.setString(_serverTokenKey, trimmed);
    }
    state = trimmed;
  }
}

final serverTokenProvider = NotifierProvider<ServerTokenController, String>(
  ServerTokenController.new,
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
