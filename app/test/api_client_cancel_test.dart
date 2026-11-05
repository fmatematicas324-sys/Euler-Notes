// Cancelación real de peticiones (M2). Usa sockets reales en 127.0.0.1 con el
// cliente de producción (`IOClient`) para comprobar que, al agotarse el tiempo
// o cancelar, la conexión se cierra de verdad y no solo deja de esperarse.
//
// Este archivo no usa `testWidgets`: así el binding de pruebas no sustituye el
// HttpClient real.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:euler_notes/core/api_client.dart';
import 'package:euler_notes/core/api_exception.dart';
import 'package:euler_notes/core/config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Servidor TCP mínimo que recibe una petición HTTP y responde con
/// [respond] (o nunca, si es `null`). Registra cuándo el cliente cierra.
class _SlowServer {
  _SlowServer._(this._socket);

  final ServerSocket _socket;
  final received = StringBuffer();
  final closedByClient = Completer<void>();
  final _clients = <Socket>[];

  static Future<_SlowServer> start({String? respond}) async {
    final server = _SlowServer._(
      await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
    );
    server._socket.listen((client) {
      server._clients.add(client);
      client.listen(
        (data) {
          server.received.write(utf8.decode(data, allowMalformed: true));
          final text = server.received.toString();
          final complete =
              text.contains('\r\n\r\n') && !text.startsWith('POST') ||
              text.endsWith('}');
          if (respond != null && complete) client.add(latin1.encode(respond));
        },
        onDone: () {
          if (!server.closedByClient.isCompleted) {
            server.closedByClient.complete();
          }
        },
        onError: (Object _) {
          if (!server.closedByClient.isCompleted) {
            server.closedByClient.complete();
          }
        },
      );
    });
    return server;
  }

  String get url => 'http://127.0.0.1:${_socket.port}';

  Future<void> close() async {
    for (final c in _clients) {
      c.destroy();
    }
    await _socket.close();
  }
}

/// Cliente que registra la petición enviada (para ver su `abortTrigger`) y
/// nunca responde salvo que se aborte.
class _RecordingClient extends http.BaseClient {
  http.BaseRequest? last;
  var abortSeen = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    last = request;
    final trigger = request is http.Abortable ? request.abortTrigger : null;
    if (trigger == null) return Completer<http.StreamedResponse>().future;
    await trigger;
    abortSeen = true;
    throw http.RequestAbortedException(request.url);
  }
}

const _short = Duration(milliseconds: 200);
const _closeDeadline = Duration(seconds: 3);

TypeMatcher<ApiException> _apiError(String code, {bool? mayHaveCompleted}) {
  var matcher = isA<ApiException>().having((e) => e.code, 'code', code);
  if (mayHaveCompleted != null) {
    matcher = matcher.having(
      (e) => e.mayHaveCompleted,
      'mayHaveCompleted',
      mayHaveCompleted,
    );
  }
  return matcher;
}

void main() {
  group('abortTrigger', () {
    test(
      'cada petición es Abortable y se aborta al agotarse el tiempo',
      () async {
        final transport = _RecordingClient();
        final client = ApiClient(
          transport,
          timeouts: const ApiTimeouts(standard: _short),
        );
        await expectLater(
          client.get('/notebooks'),
          throwsA(_apiError('timeout')),
        );
        expect(transport.last, isA<http.Abortable>());
        expect(transport.abortSeen, isTrue);
      },
    );

    test('cancel aborta la petición con el código "cancelled"', () async {
      final transport = _RecordingClient();
      final cancel = Completer<void>();
      final client = ApiClient(transport);
      final pending = client.get('/notebooks', cancel: cancel.future);
      cancel.complete();
      await expectLater(pending, throwsA(_apiError('cancelled')));
      expect(transport.abortSeen, isTrue);
    });

    test('un cancel tardío (después de responder) no tiene efecto', () async {
      final cancel = Completer<void>();
      final server = await _SlowServer.start(
        respond: 'HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n[]',
      );
      addTearDown(server.close);
      final client = ApiClient(IOClient(), baseUrl: server.url);
      expect(await client.get('/notebooks', cancel: cancel.future), isEmpty);
      cancel.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
  });

  group('IOClient real: la conexión se cierra', () {
    test('timeout sin respuesta → "timeout" y conexión cerrada', () async {
      final server = await _SlowServer.start();
      addTearDown(server.close);
      final client = ApiClient(
        IOClient(),
        baseUrl: server.url,
        timeouts: const ApiTimeouts(standard: _short),
      );
      await expectLater(
        client.get('/notebooks'),
        throwsA(_apiError('timeout', mayHaveCompleted: false)),
      );
      await server.closedByClient.future.timeout(_closeDeadline);
    });

    test(
      'timeout a mitad del cuerpo de la respuesta → conexión cerrada',
      () async {
        final server = await _SlowServer.start(
          respond: 'HTTP/1.1 200 OK\r\nContent-Length: 1000\r\n\r\n[1,2,',
        );
        addTearDown(server.close);
        final client = ApiClient(
          IOClient(),
          baseUrl: server.url,
          timeouts: const ApiTimeouts(standard: _short),
        );
        await expectLater(
          client.get('/notebooks'),
          throwsA(_apiError('timeout')),
        );
        await server.closedByClient.future.timeout(_closeDeadline);
      },
    );

    test('cancelar → "cancelled" y conexión cerrada', () async {
      final server = await _SlowServer.start();
      addTearDown(server.close);
      final cancel = Completer<void>();
      final client = ApiClient(IOClient(), baseUrl: server.url);
      final pending = client.get('/notebooks', cancel: cancel.future);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      cancel.complete();
      await expectLater(pending, throwsA(_apiError('cancelled')));
      await server.closedByClient.future.timeout(_closeDeadline);
    });

    test('POST que crea algo: el servidor lo recibió entero, así que el error '
        'avisa de que pudo completarse', () async {
      final server = await _SlowServer.start();
      addTearDown(server.close);
      final client = ApiClient(
        IOClient(),
        baseUrl: server.url,
        timeouts: const ApiTimeouts(standard: _short),
      );
      await expectLater(
        client.post('/notebooks', {'title': 'Física'}),
        throwsA(
          _apiError(
            'timeout',
            mayHaveCompleted: true,
          ).having((e) => e.message, 'message', contains('pudo completarse')),
        ),
      );
      await server.closedByClient.future.timeout(_closeDeadline);
      expect(server.received.toString(), contains('"title":"Física"'));
    });

    test('POST idempotente (/compute) no avisa de efectos', () async {
      final server = await _SlowServer.start();
      addTearDown(server.close);
      final client = ApiClient(
        IOClient(),
        baseUrl: server.url,
        timeouts: const ApiTimeouts(standard: _short),
      );
      await expectLater(
        client.post('/compute', {'expr': 'x'}, idempotent: true),
        throwsA(_apiError('timeout', mayHaveCompleted: false)),
      );
    });

    test('puerto cerrado → "network_error" (no "timeout")', () async {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();
      final client = ApiClient(IOClient(), baseUrl: 'http://127.0.0.1:$port');
      await expectLater(
        client.get('/notebooks'),
        throwsA(_apiError('network_error', mayHaveCompleted: false)),
      );
      // Un POST que crea algo no puede afirmar que no se hizo.
      await expectLater(
        client.post('/notebooks', {'title': 'x'}),
        throwsA(_apiError('network_error', mayHaveCompleted: true)),
      );
    });
  });

  group('mensajes', () {
    test('network_error distingue si la operación pudo completarse', () {
      expect(
        errorMessage(const ApiException(code: 'network_error', message: '')),
        contains('¿Está arrancado?'),
      );
      expect(
        errorMessage(
          const ApiException(
            code: 'network_error',
            message: '',
            mayHaveCompleted: true,
          ),
        ),
        contains('pudo completarse'),
      );
    });
  });
}
