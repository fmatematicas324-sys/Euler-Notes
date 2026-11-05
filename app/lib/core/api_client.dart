import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'api_exception.dart';
import 'config.dart';
import 'server_settings.dart';

/// Cliente REST mínimo para el backend local. Las features lo usan desde su
/// capa `data/`; nunca desde widgets.
class ApiClient {
  ApiClient(
    this._http, {
    String baseUrl = apiBaseUrl,
    String token = '',
    this.timeouts = const ApiTimeouts(),
  }) : _baseUri = Uri.parse(baseUrl),
       _auth = token.isEmpty ? const {} : {'Authorization': 'Bearer $token'};

  final http.Client _http;
  final Uri _baseUri;

  /// Cabecera de autenticación (vacía si no hay token configurado).
  final Map<String, String> _auth;

  /// Tiempos máximos por tipo de petición. Cada método usa uno por defecto y
  /// acepta `timeout` para casos concretos (p. ej. `/compute` o `/health`).
  final ApiTimeouts timeouts;

  Map<String, String> get _jsonHeaders => {
    ..._auth,
    'Content-Type': 'application/json',
  };

  Future<dynamic> get(String path, {Duration? timeout}) => _send(
    () => _http.get(_uri(path), headers: _auth),
    timeout ?? timeouts.standard,
  );

  Future<dynamic> post(String path, Object body, {Duration? timeout}) => _send(
    () => _http.post(_uri(path), headers: _jsonHeaders, body: jsonEncode(body)),
    timeout ?? timeouts.standard,
  );

  Future<dynamic> put(String path, Object body, {Duration? timeout}) => _send(
    () => _http.put(_uri(path), headers: _jsonHeaders, body: jsonEncode(body)),
    timeout ?? timeouts.standard,
  );

  Future<void> delete(String path, {Duration? timeout}) => _send(
    () => _http.delete(_uri(path), headers: _auth),
    timeout ?? timeouts.standard,
  );

  /// POST con cuerpo binario (p. ej. un PDF) y respuesta JSON.
  Future<dynamic> postBinary(
    String path,
    Uint8List body, {
    required String contentType,
    Map<String, String>? query,
    Duration? timeout,
  }) => _send(
    () => _http.post(
      _uri(path).replace(queryParameters: query),
      headers: {..._auth, 'Content-Type': contentType},
      body: body,
    ),
    timeout ?? timeouts.upload,
  );

  /// GET con respuesta binaria (p. ej. un PDF).
  Future<Uint8List> getBytes(String path, {Duration? timeout}) async =>
      (await _request(
        () => _http.get(_uri(path), headers: _auth),
        timeout ?? timeouts.download,
      )).bodyBytes;

  /// POST con cuerpo JSON y respuesta binaria (p. ej. una imagen PNG).
  Future<Uint8List> postForBytes(
    String path,
    Object body, {
    Duration? timeout,
  }) async {
    final response = await _request(
      () =>
          _http.post(_uri(path), headers: _jsonHeaders, body: jsonEncode(body)),
      timeout ?? timeouts.render,
    );
    return response.bodyBytes;
  }

  Uri _uri(String path) => _baseUri.resolve(path);

  Future<dynamic> _send(
    Future<http.Response> Function() request,
    Duration timeout,
  ) async {
    final response = await _request(request, timeout);
    return response.body.isEmpty
        ? null
        : _decode(utf8.decode(response.bodyBytes));
  }

  /// Ejecuta la petición y convierte los fallos de red, el tiempo de espera
  /// agotado y las respuestas de error del backend en [ApiException].
  /// Devuelve la respuesta si es 2xx.
  ///
  /// Nota: al agotarse [timeout] la app deja de esperar, pero `package:http`
  /// no cancela la conexión subyacente; se cierra cuando el servidor responde
  /// o el sistema la corta.
  Future<http.Response> _request(
    Future<http.Response> Function() request,
    Duration timeout,
  ) async {
    final http.Response response;
    try {
      response = await request().timeout(timeout);
    } on TimeoutException {
      throw ApiException(
        code: 'timeout',
        message:
            'El servidor no respondió en ${_seconds(timeout)}. '
            'Comprueba la conexión y que el backend esté en marcha.',
      );
    } on Exception catch (e) {
      throw ApiException(
        code: 'network_error',
        message: 'No se pudo conectar con el backend ($e)',
      );
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }

    Object? body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      body = null;
    }
    final error = body is Map<String, dynamic> ? body['error'] : null;
    if (error is Map<String, dynamic>) {
      throw ApiException(
        code: error['code'] as String? ?? 'http_error',
        message: error['message'] as String? ?? 'Error desconocido',
        statusCode: response.statusCode,
      );
    }
    throw ApiException(
      code: 'http_error',
      message: 'Respuesta inesperada del backend',
      statusCode: response.statusCode,
    );
  }

  static String _seconds(Duration d) {
    final s = d.inMilliseconds / 1000;
    return s == s.roundToDouble() ? '${s.toInt()} s' : '$s s';
  }

  dynamic _decode(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      throw const ApiException(
        code: 'bad_response',
        message: 'El backend devolvió una respuesta que no es JSON',
      );
    }
  }
}

final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// Se reconstruye (y con él todos los repositorios) al cambiar el servidor.
final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    ref.watch(httpClientProvider),
    baseUrl: ref.watch(serverUrlProvider),
    token: ref.watch(serverTokenProvider),
  ),
);
