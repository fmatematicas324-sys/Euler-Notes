import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../../../core/local_db/local_database_provider.dart';
import '../../../core/server_settings.dart';
import '../domain/drawing.dart';
import '../domain/stroke.dart';
import 'local_drawings_repository.dart';

/// Dibujos de los bloques ` ```ink `. Dos implementaciones: el servidor
/// ([ApiDrawingsRepository]) o la copia de la tablet
/// ([LocalDrawingsRepository], modo sin conexión).
abstract interface class DrawingsRepository {
  Future<Drawing> create(String noteId);

  Future<Drawing> get(String id);

  Future<Drawing> saveStrokes(String id, List<Stroke> strokes);
}

class ApiDrawingsRepository implements DrawingsRepository {
  ApiDrawingsRepository(this._api);

  final ApiClient _api;

  @override
  Future<Drawing> create(String noteId) async => Drawing.fromJson(
    await _api.post('/notes/$noteId/drawings', const <String, Object>{})
        as Map<String, dynamic>,
  );

  @override
  Future<Drawing> get(String id) async =>
      Drawing.fromJson(await _api.get('/drawings/$id') as Map<String, dynamic>);

  @override
  Future<Drawing> saveStrokes(String id, List<Stroke> strokes) async =>
      Drawing.fromJson(
        await _api.put('/drawings/$id', {
          'strokes': [for (final s in strokes) s.toJson()],
        }) as Map<String, dynamic>,
      );
}

final drawingsRepositoryProvider = Provider<DrawingsRepository>(
  (ref) => ref.watch(offlineModeProvider)
      ? LocalDrawingsRepository(ref.watch(localDatabaseProvider))
      : ApiDrawingsRepository(ref.watch(apiClientProvider)),
);

/// Dibujo por id (para las vistas previas); se invalida al editarlo.
final drawingProvider = FutureProvider.autoDispose.family<Drawing, String>(
  (ref, id) => ref.watch(drawingsRepositoryProvider).get(id),
  retry: (_, _) => null,
);
