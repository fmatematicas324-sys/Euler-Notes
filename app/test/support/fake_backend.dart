import 'dart:convert';
import 'dart:typed_data';

import 'package:cuaderno_cientifico/app.dart';
import 'package:cuaderno_cientifico/core/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// PNG transparente de 1×1 px: válido para `Image.memory`.
final kTransparentPng = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]); // fmt: skip

/// Backend en memoria con el mismo contrato HTTP que `backend/`.
class FakeBackend {
  final notebooks = <int, Map<String, dynamic>>{};
  final notes = <int, Map<String, dynamic>>{};
  final computeRequests = <Map<String, dynamic>>[];
  final noteUpdates = <Map<String, dynamic>>[];
  final plotRequests = <Map<String, dynamic>>[];
  final diagramRequests = <Map<String, dynamic>>[];
  final documents = <int, Map<String, dynamic>>{};
  final documentFiles = <int, List<int>>{};
  final pageTextRequests = <int>[];
  final drawings = <int, Map<String, dynamic>>{};

  /// Si no es `null`, la subida de PDF falla con este (status, código, mensaje).
  (int, String, String)? uploadError;

  /// Respuesta de `/plot`. Por defecto, un PNG válido.
  http.Response Function(Map<String, dynamic> request) onPlot = (_) =>
      http.Response.bytes(
        kTransparentPng,
        200,
        headers: {'content-type': 'image/png'},
      );

  /// Si es `true`, todas las peticiones fallan como si no hubiera conexión.
  bool offline = false;

  /// Respuesta de `/compute`: (status, cuerpo).
  (int, Map<String, dynamic>) Function(Map<String, dynamic> request) onCompute =
      (_) => (200, {'result_latex': r'2 x', 'result_text': '2*x'});

  int _nextId = 1;
  int _clock = 0;

  late final MockClient client = MockClient(_handle);

  String _now() => DateTime.utc(2026, 11, 3, 10, 0, _clock++).toIso8601String();

  int addNotebook(String title, {String cover = 'classic'}) {
    final id = _nextId++;
    final ts = _now();
    notebooks[id] = {
      'id': id,
      'title': title,
      'cover': cover,
      'created_at': ts,
      'updated_at': ts,
    };
    return id;
  }

  int addNote(
    int notebookId,
    String title, {
    String content = '',
    String paper = 'blank',
  }) {
    final id = _nextId++;
    final ts = _now();
    notes[id] = {
      'id': id,
      'notebook_id': notebookId,
      'title': title,
      'content': content,
      'paper': paper,
      'created_at': ts,
      'updated_at': ts,
    };
    return id;
  }

  Future<http.Response> _handle(http.Request request) async {
    if (offline) throw http.ClientException('sin conexión');
    final isJson = (request.headers['content-type'] ?? '').contains('json');
    final body = request.body.isEmpty || !isJson
        ? <String, dynamic>{}
        : jsonDecode(request.body) as Map<String, dynamic>;
    final segments = request.url.pathSegments;

    switch ((request.method, segments)) {
      case ('GET', ['health']):
        return _json({'status': 'ok', 'version': '0.1.0'});
      case ('GET', ['notebooks']):
        return _json(notebooks.values.toList().reversed.toList());
      case ('POST', ['notebooks']):
        final id = addNotebook(
          body['title'] as String,
          cover: body['cover'] as String? ?? 'classic',
        );
        return _json(notebooks[id]!, 201);
      case ('PUT', ['notebooks', final id]):
        final notebook = notebooks[int.parse(id)];
        if (notebook == null) return _notFound();
        notebook
          ..addAll(body)
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
      case ('POST', ['plot']):
        plotRequests.add(body);
        return onPlot(body);
      case ('POST', ['diagram']):
        diagramRequests.add(body);
        return onPlot(body);
      case ('GET', ['documents']):
        return _json(documents.values.toList().reversed.toList());
      case ('POST', ['documents']):
        if (uploadError case (final status, final code, final message)) {
          return _json({
            'error': {'code': code, 'message': message},
          }, status);
        }
        final id = _nextId++;
        documentFiles[id] = request.bodyBytes;
        documents[id] = {
          'id': id,
          'filename':
              request.url.queryParameters['filename'] ?? 'documento.pdf',
          'size': request.bodyBytes.length,
          'pages': 2,
          'created_at': _now(),
        };
        return _json(documents[id]!, 201);
      case ('GET', ['documents', final id, 'file']):
        final bytes = documentFiles[int.parse(id)];
        return bytes == null
            ? _notFound()
            : http.Response.bytes(
                bytes,
                200,
                headers: {'content-type': 'application/pdf'},
              );
      case ('GET', ['documents', final id, 'pages', final page, 'text']):
        if (!documents.containsKey(int.parse(id))) return _notFound();
        pageTextRequests.add(int.parse(page));
        return _json({
          'page': int.parse(page),
          'text': 'Página $page: ∫ x² dx',
          'latex': 'Página $page: \\int x^{2} dx',
        });
      case ('DELETE', ['documents', final id]):
        documentFiles.remove(int.parse(id));
        return documents.remove(int.parse(id)) == null
            ? _notFound()
            : http.Response('', 204);
      case ('POST', ['notes', final id, 'drawings']):
        if (!notes.containsKey(int.parse(id))) return _notFound();
        final drawingId = _nextId++;
        drawings[drawingId] = {
          'id': drawingId,
          'note_id': int.parse(id),
          'width': 1000.0,
          'height': 700.0,
          'strokes': <Object>[],
          'created_at': _now(),
          'updated_at': _now(),
        };
        return _json(drawings[drawingId]!, 201);
      case ('GET', ['drawings', final id]):
        final drawing = drawings[int.parse(id)];
        return drawing == null ? _notFound() : _json(drawing);
      case ('PUT', ['drawings', final id]):
        final drawing = drawings[int.parse(id)];
        if (drawing == null) return _notFound();
        drawing
          ..addAll(body)
          ..['updated_at'] = _now();
        return _json(drawing);
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
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        httpClientProvider.overrideWithValue(backend.client),
        ...overrides,
      ],
      child: const CuadernoApp(),
    ),
  );
  await tester.pumpAndSettle();
}
