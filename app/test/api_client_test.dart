import 'dart:convert';
import 'dart:typed_data';

import 'package:euler_notes/core/api_client.dart';
import 'package:euler_notes/core/api_exception.dart';
import 'package:euler_notes/core/config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('decodifica respuestas JSON correctas con UTF-8', () async {
    final client = ApiClient(
      MockClient((request) async {
        expect(request.url.toString(), 'http://127.0.0.1:8000/notebooks');
        return http.Response.bytes(
          utf8.encode(
            jsonEncode([
              {'id': 1, 'title': 'Física'},
            ]),
          ),
          200,
        );
      }),
    );
    final body = await client.get('/notebooks') as List<dynamic>;
    expect((body.first as Map)['title'], 'Física');
  });

  test('envía JSON en POST', () async {
    final client = ApiClient(
      MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.headers['Content-Type'], startsWith('application/json'));
        expect(jsonDecode(request.body), {'expr': 'x^2', 'op': 'diff'});
        return _json({'result_text': '2*x'}, 200);
      }),
    );
    final body = await client.post('/compute', {'expr': 'x^2', 'op': 'diff'});
    expect((body as Map)['result_text'], '2*x');
  });

  test('convierte el formato de error del backend en ApiException', () async {
    final client = ApiClient(
      MockClient(
        (_) async => _json({
          'error': {'code': 'invalid_expression', 'message': 'No válida'},
        }, 400),
      ),
    );
    await expectLater(
      client.post('/compute', {'expr': '__', 'op': 'simplify'}),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', 'invalid_expression')
            .having((e) => e.statusCode, 'statusCode', 400),
      ),
    );
  });

  test('postForBytes devuelve el cuerpo binario', () async {
    final png = [0x89, 0x50, 0x4E, 0x47];
    final client = ApiClient(
      MockClient((request) async {
        expect(jsonDecode(request.body), {
          'exprs': ['x'],
        });
        return http.Response.bytes(
          png,
          200,
          headers: {'content-type': 'image/png'},
        );
      }),
    );
    expect(
      await client.postForBytes('/plot', {
        'exprs': ['x'],
      }),
      png,
    );
  });

  test('postForBytes convierte errores JSON en ApiException', () async {
    final client = ApiClient(
      MockClient(
        (_) async => _json({
          'error': {'code': 'compute_error', 'message': 'Sin valores reales'},
        }, 422),
      ),
    );
    await expectLater(
      client.postForBytes('/plot', {
        'exprs': ['sqrt(-1)'],
      }),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', 'compute_error')
            .having((e) => e.statusCode, 'statusCode', 422),
      ),
    );
  });

  test('postBinary envía bytes con su tipo y query', () async {
    final client = ApiClient(
      MockClient((request) async {
        expect(request.url.queryParameters, {'filename': 'a.pdf'});
        expect(request.headers['Content-Type'], 'application/pdf');
        expect(request.bodyBytes, [1, 2, 3]);
        return _json({'id': 1}, 201);
      }),
    );
    final body = await client.postBinary(
      '/documents',
      Uint8List.fromList([1, 2, 3]),
      contentType: 'application/pdf',
      query: {'filename': 'a.pdf'},
    );
    expect((body as Map)['id'], 1);
  });

  test('getBytes devuelve el cuerpo binario', () async {
    final client = ApiClient(
      MockClient((_) async => http.Response.bytes([7, 8], 200)),
    );
    expect(await client.getBytes('/documents/1/file'), [7, 8]);
  });

  test('DELETE con 204 sin cuerpo no falla', () async {
    final client = ApiClient(MockClient((_) async => http.Response('', 204)));
    await client.delete('/notes/1');
  });

  test('fallo de red se convierte en network_error', () async {
    final client = ApiClient(
      MockClient((_) async => throw http.ClientException('sin conexión')),
    );
    await expectLater(
      client.get('/health'),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'network_error'),
      ),
    );
  });

  group('tiempos de espera', () {
    // Un servidor que tarda [delay] en contestar.
    MockClient slowServer(Duration delay) => MockClient((request) async {
      await Future<void>.delayed(delay);
      return _json({'ok': true}, 200);
    });

    const tiny = Duration(milliseconds: 50);
    const roomy = Duration(seconds: 5);

    test('una respuesta lenta falla con code "timeout"', () async {
      final client = ApiClient(
        slowServer(const Duration(milliseconds: 500)),
        timeouts: const ApiTimeouts(standard: tiny),
      );
      await expectLater(
        client.get('/notebooks'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'timeout')
              .having((e) => e.message, 'message', contains('no respondió')),
        ),
      );
    });

    test('una respuesta a tiempo no cambia', () async {
      final client = ApiClient(
        slowServer(const Duration(milliseconds: 10)),
        timeouts: const ApiTimeouts(standard: roomy),
      );
      expect(await client.get('/notebooks'), {'ok': true});
    });

    test(
      'el parámetro timeout tiene prioridad sobre el valor por defecto',
      () async {
        final client = ApiClient(
          slowServer(const Duration(milliseconds: 200)),
          timeouts: const ApiTimeouts(standard: tiny),
        );
        expect(await client.get('/health', timeout: roomy), {'ok': true});
      },
    );

    test('cada tipo de petición usa su tiempo por defecto', () async {
      // Todos los tiempos son mínimos salvo el que debería usar cada método.
      ApiClient clientWith(ApiTimeouts timeouts) => ApiClient(
        slowServer(const Duration(milliseconds: 200)),
        timeouts: timeouts,
      );
      const allTiny = ApiTimeouts(
        health: tiny,
        standard: tiny,
        compute: tiny,
        render: tiny,
        download: tiny,
        upload: tiny,
      );
      expect(
        await clientWith(
          const ApiTimeouts(
            health: tiny,
            standard: tiny,
            compute: tiny,
            render: tiny,
            download: tiny,
            upload: roomy,
          ),
        ).postBinary(
          '/documents',
          Uint8List(4),
          contentType: 'application/pdf',
        ),
        {'ok': true},
      );
      expect(
        await clientWith(
          const ApiTimeouts(
            health: tiny,
            standard: tiny,
            compute: tiny,
            render: tiny,
            download: roomy,
            upload: tiny,
          ),
        ).getBytes('/documents/1/file'),
        isNotEmpty,
      );
      expect(
        await clientWith(
          const ApiTimeouts(
            health: tiny,
            standard: tiny,
            compute: tiny,
            render: roomy,
            download: tiny,
            upload: tiny,
          ),
        ).postForBytes('/plot', const {}),
        isNotEmpty,
      );
      await expectLater(
        clientWith(allTiny).postBinary(
          '/documents',
          Uint8List(4),
          contentType: 'application/pdf',
        ),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'timeout')),
      );
    });
  });

  group('token de acceso', () {
    test('se envía en todas las peticiones', () async {
      final seen = <String?>[];
      final client = ApiClient(
        MockClient((request) async {
          seen.add(request.headers['Authorization']);
          return http.Response.bytes(utf8.encode('{}'), 200);
        }),
        token: 'secreto',
      );
      await client.get('/a');
      await client.post('/a', const {});
      await client.put('/a', const {});
      await client.delete('/a');
      await client.getBytes('/a');
      await client.postForBytes('/a', const {});
      await client.postBinary(
        '/a',
        Uint8List(1),
        contentType: 'application/pdf',
      );
      expect(seen, List.filled(7, 'Bearer secreto'));
    });

    test('sin token no se envía la cabecera', () async {
      final client = ApiClient(
        MockClient((request) async {
          expect(request.headers.containsKey('Authorization'), isFalse);
          return http.Response.bytes(utf8.encode('{}'), 200);
        }),
      );
      await client.get('/a');
    });

    test('un 401 del backend llega como ApiException', () async {
      final client = ApiClient(
        MockClient(
          (_) async => _json({
            'error': {'code': 'unauthorized', 'message': 'Token incorrecto'},
          }, 401),
        ),
        token: 'otro',
      );
      await expectLater(
        client.get('/notebooks'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'unauthorized')
              .having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });
  });
}
