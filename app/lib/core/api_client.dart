import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'api_exception.dart';
import 'config.dart';

/// Cliente REST mínimo para el backend local. Las features lo usan desde su
/// capa `data/`; nunca desde widgets.
class ApiClient {
  ApiClient(this._http, {String baseUrl = apiBaseUrl})
    : _baseUri = Uri.parse(baseUrl);

  final http.Client _http;
  final Uri _baseUri;

  static const _jsonHeaders = {'Content-Type': 'application/json'};

  Future<dynamic> get(String path) => _send(() => _http.get(_uri(path)));

  Future<dynamic> post(String path, Object body) => _send(
    () => _http.post(_uri(path), headers: _jsonHeaders, body: jsonEncode(body)),
  );

  Future<dynamic> put(String path, Object body) => _send(
    () => _http.put(_uri(path), headers: _jsonHeaders, body: jsonEncode(body)),
  );

  Future<void> delete(String path) => _send(() => _http.delete(_uri(path)));

  /// POST con cuerpo binario (p. ej. un PDF) y respuesta JSON.
  Future<dynamic> postBinary(
    String path,
    Uint8List body, {
    required String contentType,
    Map<String, String>? query,
  }) => _send(
    () => _http.post(
      _uri(path).replace(queryParameters: query),
      headers: {'Content-Type': contentType},
      body: body,
    ),
  );

  /// GET con respuesta binaria (p. ej. un PDF).
  Future<Uint8List> getBytes(String path) async =>
      (await _request(() => _http.get(_uri(path)))).bodyBytes;

  /// POST con cuerpo JSON y respuesta binaria (p. ej. una imagen PNG).
  Future<Uint8List> postForBytes(String path, Object body) async {
    final response = await _request(
      () =>
          _http.post(_uri(path), headers: _jsonHeaders, body: jsonEncode(body)),
    );
    return response.bodyBytes;
  }

  Uri _uri(String path) => _baseUri.resolve(path);

  Future<dynamic> _send(Future<http.Response> Function() request) async {
    final response = await _request(request);
    return response.body.isEmpty
        ? null
        : _decode(utf8.decode(response.bodyBytes));
  }

  /// Ejecuta la petición y convierte los fallos de red y las respuestas de
  /// error del backend en [ApiException]. Devuelve la respuesta si es 2xx.
  Future<http.Response> _request(
    Future<http.Response> Function() request,
  ) async {
    final http.Response response;
    try {
      response = await request();
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

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(ref.watch(httpClientProvider)),
);
