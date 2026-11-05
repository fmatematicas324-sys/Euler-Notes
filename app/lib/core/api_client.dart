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

  // Todos los métodos aceptan:
  //  * `timeout`: sustituye al tiempo por defecto de ese tipo de petición.
  //  * `cancel`: al completarse, cancela la petición (código `cancelled`).

  Future<dynamic> get(String path, {Duration? timeout, Future<void>? cancel}) =>
      _send(
        'GET',
        _uri(path),
        headers: _auth,
        timeout: timeout ?? timeouts.standard,
        cancel: cancel,
      );

  /// [idempotent]: `true` si repetir la petición no crea nada nuevo (p. ej.
  /// `/compute`). Si es `false` (por defecto) y la respuesta no llega, el
  /// error avisa de que la operación pudo completarse en el servidor.
  Future<dynamic> post(
    String path,
    Object body, {
    Duration? timeout,
    Future<void>? cancel,
    bool idempotent = false,
  }) => _send(
    'POST',
    _uri(path),
    headers: _jsonHeaders,
    body: jsonEncode(body),
    timeout: timeout ?? timeouts.standard,
    cancel: cancel,
    idempotent: idempotent,
  );

  Future<dynamic> put(
    String path,
    Object body, {
    Duration? timeout,
    Future<void>? cancel,
  }) => _send(
    'PUT',
    _uri(path),
    headers: _jsonHeaders,
    body: jsonEncode(body),
    timeout: timeout ?? timeouts.standard,
    cancel: cancel,
  );

  Future<void> delete(String path, {Duration? timeout, Future<void>? cancel}) =>
      _send(
        'DELETE',
        _uri(path),
        headers: _auth,
        timeout: timeout ?? timeouts.standard,
        cancel: cancel,
      );

  /// POST con cuerpo binario (p. ej. un PDF) y respuesta JSON. Crea un recurso:
  /// no es idempotente.
  Future<dynamic> postBinary(
    String path,
    Uint8List body, {
    required String contentType,
    Map<String, String>? query,
    Duration? timeout,
    Future<void>? cancel,
  }) => _send(
    'POST',
    _uri(path).replace(queryParameters: query),
    headers: {..._auth, 'Content-Type': contentType},
    body: body,
    timeout: timeout ?? timeouts.upload,
    cancel: cancel,
    idempotent: false,
  );

  /// GET con respuesta binaria (p. ej. un PDF).
  Future<Uint8List> getBytes(
    String path, {
    Duration? timeout,
    Future<void>? cancel,
  }) async => (await _request(
    'GET',
    _uri(path),
    headers: _auth,
    timeout: timeout ?? timeouts.download,
    cancel: cancel,
  )).bodyBytes;

  /// POST con cuerpo JSON y respuesta binaria (p. ej. una imagen PNG de
  /// `/plot`). Por defecto idempotente: solo dibuja, no guarda nada.
  Future<Uint8List> postForBytes(
    String path,
    Object body, {
    Duration? timeout,
    Future<void>? cancel,
    bool idempotent = true,
  }) async => (await _request(
    'POST',
    _uri(path),
    headers: _jsonHeaders,
    body: jsonEncode(body),
    timeout: timeout ?? timeouts.render,
    cancel: cancel,
    idempotent: idempotent,
  )).bodyBytes;

  Uri _uri(String path) => _baseUri.resolve(path);

  Future<dynamic> _send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    Object? body,
    required Duration timeout,
    Future<void>? cancel,
    bool idempotent = true,
  }) async {
    final response = await _request(
      method,
      uri,
      headers: headers,
      body: body,
      timeout: timeout,
      cancel: cancel,
      idempotent: idempotent,
    );
    return response.body.isEmpty
        ? null
        : _decode(utf8.decode(response.bodyBytes));
  }

  /// Ejecuta la petición y convierte los fallos de red, el tiempo agotado, la
  /// cancelación y las respuestas de error del backend en [ApiException].
  /// Devuelve la respuesta si es 2xx.
  ///
  /// Cancelación real: la petición es un [http.AbortableRequest]. Al agotarse
  /// [timeout] o completarse [cancel], su `abortTrigger` se completa y
  /// `IOClient` (Android, Linux) y `BrowserClient` (Web) cortan la conexión,
  /// también mientras se recibe el cuerpo de la respuesta. Si un cliente no
  /// admite la cancelación (p. ej. `MockClient` en las pruebas), la app deja de
  /// esperar igualmente, aunque la conexión pueda seguir abierta.
  ///
  /// Cortar la conexión no deshace nada en el servidor: si la petición ya se
  /// envió, pudo completarse. Por eso las operaciones no idempotentes
  /// ([idempotent] `false`) marcan [ApiException.mayHaveCompleted].
  Future<http.Response> _request(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    Object? body,
    required Duration timeout,
    Future<void>? cancel,
    bool idempotent = true,
  }) async {
    final trigger = Completer<void>();
    var reason = _AbortReason.none;
    var finished = false;
    void abort(_AbortReason why) {
      if (finished || trigger.isCompleted) return;
      reason = why;
      trigger.complete();
    }

    final timer = Timer(timeout, () => abort(_AbortReason.timeout));
    cancel?.then(
      (_) => abort(_AbortReason.cancelled),
      onError: (Object _) => abort(_AbortReason.cancelled),
    );

    final request = http.AbortableRequest(
      method,
      uri,
      abortTrigger: trigger.future,
    )..headers.addAll(headers);
    if (body is String) {
      request.body = body;
    } else if (body is List<int>) {
      request.bodyBytes = body;
    }

    final work = Future.sync(
      () async => http.Response.fromStream(await _http.send(request)),
    );
    final http.Response response;
    try {
      // Si el cliente no corta la conexión al abortar, `trigger` gana la
      // carrera y se deja de esperar igualmente.
      response = await Future.any([
        work,
        trigger.future.then<http.Response>((_) => throw const _Aborted()),
      ]);
    } on Exception catch (e) {
      work.ignore();
      if (reason != _AbortReason.none) {
        throw _abortError(reason, timeout, idempotent: idempotent);
      }
      throw ApiException(
        code: 'network_error',
        message: 'No se pudo conectar con el backend ($e)',
        mayHaveCompleted: !idempotent,
      );
    } finally {
      finished = true;
      timer.cancel();
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }

    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      decoded = null;
    }
    final error = decoded is Map<String, dynamic> ? decoded['error'] : null;
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

  static ApiException _abortError(
    _AbortReason reason,
    Duration timeout, {
    required bool idempotent,
  }) {
    const unknownOutcome =
        ' La operación pudo completarse en el servidor: '
        'comprueba el resultado antes de repetirla.';
    return switch (reason) {
      _AbortReason.timeout => ApiException(
        code: 'timeout',
        message:
            'El servidor no respondió en ${_seconds(timeout)}.'
            '${idempotent ? ' Comprueba la conexión y que el backend esté en marcha.' : unknownOutcome}',
        mayHaveCompleted: !idempotent,
      ),
      _ => ApiException(
        code: 'cancelled',
        message: 'Petición cancelada.${idempotent ? '' : unknownOutcome}',
        mayHaveCompleted: !idempotent,
      ),
    };
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

enum _AbortReason { none, timeout, cancelled }

/// Señal interna: el disparador de cancelación ganó la carrera.
class _Aborted implements Exception {
  const _Aborted();
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
