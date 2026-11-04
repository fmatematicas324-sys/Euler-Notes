import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../domain/drawing.dart';
import '../domain/stroke.dart';

class DrawingsRepository {
  DrawingsRepository(this._api);

  final ApiClient _api;

  Future<Drawing> create(int noteId) async => Drawing.fromJson(
    await _api.post('/notes/$noteId/drawings', const <String, Object>{})
        as Map<String, dynamic>,
  );

  Future<Drawing> get(int id) async =>
      Drawing.fromJson(await _api.get('/drawings/$id') as Map<String, dynamic>);

  Future<Drawing> saveStrokes(int id, List<Stroke> strokes) async =>
      Drawing.fromJson(
        await _api.put('/drawings/$id', {
          'strokes': [for (final s in strokes) s.toJson()],
        }) as Map<String, dynamic>,
      );
}

final drawingsRepositoryProvider = Provider<DrawingsRepository>(
  (ref) => DrawingsRepository(ref.watch(apiClientProvider)),
);

/// Dibujo por id (para las vistas previas); se invalida al editarlo.
final drawingProvider = FutureProvider.autoDispose.family<Drawing, int>(
  (ref, id) => ref.watch(drawingsRepositoryProvider).get(id),
  retry: (_, _) => null,
);
