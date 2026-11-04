import 'dart:convert';

import 'package:cuaderno_cientifico/core/api_client.dart';
import 'package:cuaderno_cientifico/core/api_exception.dart';
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
}
