import 'dart:convert';

import 'package:cuaderno_cientifico/app.dart';
import 'package:cuaderno_cientifico/core/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Backend en memoria con el mismo contrato HTTP que `backend/`.
class FakeBackend {
  final notebooks = <int, Map<String, dynamic>>{};
  final notes = <int, Map<String, dynamic>>{};
  final computeRequests = <Map<String, dynamic>>[];
  final noteUpdates = <Map<String, dynamic>>[];

  /// Si es `true`, todas las peticiones fallan como si no hubiera conexión.
  bool offline = false;

  /// Respuesta de `/compute`: (status, cuerpo).
  (int, Map<String, dynamic>) Function(Map<String, dynamic> request) onCompute =
      (_) => (200, {'result_latex': r'2 x', 'result_text': '2*x'});

  int _nextId = 1;
  int _clock = 0;

  late final MockClient client = MockClient(_handle);

  String _now() => DateTime.utc(2026, 11, 3, 10, 0, _clock++).toIso8601String();

  int addNotebook(String title) {
    final id = _nextId++;
    final ts = _now();
    notebooks[id] = {
      'id': id,
      'title': title,
      'created_at': ts,
      'updated_at': ts,
    };
    return id;
  }

  int addNote(int notebookId, String title, {String content = ''}) {
    final id = _nextId++;
    final ts = _now();
    notes[id] = {
      'id': id,
      'notebook_id': notebookId,
      'title': title,
      'content': content,
      'created_at': ts,
      'updated_at': ts,
    };
    return id;
  }

  Future<http.Response> _handle(http.Request request) async {
    if (offline) throw http.ClientException('sin conexión');
    final body = request.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(request.body) as Map<String, dynamic>;
    final segments = request.url.pathSegments;

    switch ((request.method, segments)) {
      case ('GET', ['health']):
        return _json({'status': 'ok', 'version': '0.1.0'});
      case ('GET', ['notebooks']):
        return _json(notebooks.values.toList().reversed.toList());
      case ('POST', ['notebooks']):
        return _json(notebooks[addNotebook(body['title'] as String)]!, 201);
      case ('PUT', ['notebooks', final id]):
        final notebook = notebooks[int.parse(id)];
        if (notebook == null) return _notFound();
        notebook
          ..['title'] = body['title']
          ..['updated_at'] = _now();
        return _json(notebook);
      case ('DELETE', ['notebooks', final id]):
        if (notebooks.remove(int.parse(id)) == null) return _notFound();
        notes.removeWhere((_, n) => n['notebook_id'] == int.parse(id));
        return http.Response('', 204);
      case ('GET', ['notebooks', final id, 'notes']):
        if (!notebooks.containsKey(int.parse(id))) return _notFound();
        return _json([
          for (final n in notes.values.toList().reversed)
            if (n['notebook_id'] == int.parse(id)) Map.of(n)..remove('content'),
        ]);
      case ('POST', ['notebooks', final id, 'notes']):
        if (!notebooks.containsKey(int.parse(id))) return _notFound();
        return _json(
          notes[addNote(int.parse(id), body['title'] as String)]!,
          201,
        );
      case ('GET', ['notes', final id]):
        final note = notes[int.parse(id)];
        return note == null ? _notFound() : _json(note);
      case ('PUT', ['notes', final id]):
        final note = notes[int.parse(id)];
        if (note == null) return _notFound();
        noteUpdates.add(body);
        note
          ..addAll(body)
          ..['updated_at'] = _now();
        return _json(note);
      case ('DELETE', ['notes', final id]):
        return notes.remove(int.parse(id)) == null
            ? _notFound()
            : http.Response('', 204);
      case ('POST', ['compute']):
        computeRequests.add(body);
        final (status, response) = onCompute(body);
        return _json(response, status);
    }
    return _notFound();
  }

  http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  http.Response _notFound() => _json({
    'error': {'code': 'not_found', 'message': 'No existe'},
  }, 404);
}

/// Monta la app completa contra [backend] con un tamaño de ventana dado.
Future<void> pumpApp(
  WidgetTester tester,
  FakeBackend backend, {
  Size size = const Size(1280, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [httpClientProvider.overrideWithValue(backend.client)],
      child: const CuadernoApp(),
    ),
  );
  await tester.pumpAndSettle();
}
