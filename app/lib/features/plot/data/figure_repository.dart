import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../domain/figure_spec.dart';

/// Pide figuras al backend (`/plot`, `/diagram`) y guarda las últimas en
/// memoria: la vista previa se reconstruye en cada pulsación y no debe volver a
/// pedir la misma imagen.
class FigureRepository {
  FigureRepository(this._api);

  static const cacheSize = 32;

  final ApiClient _api;
  final _cache = <String, Uint8List>{}; // orden de inserción = LRU

  Future<Uint8List> render(
    FigureSpec spec, {
    required bool dark,
    required int width,
    required int height,
    required double scale,
  }) async {
    final body = spec.toRequestJson(
      dark: dark,
      width: width,
      height: height,
      scale: scale,
    );
    final key = '${spec.endpoint} ${jsonEncode(body)}';
    final cached = _cache.remove(key);
    if (cached != null) return _cache[key] = cached;

    final png = await _api.postForBytes(spec.endpoint, body);
    _cache[key] = png;
    if (_cache.length > cacheSize) _cache.remove(_cache.keys.first);
    return png;
  }
}

final figureRepositoryProvider = Provider<FigureRepository>(
  (ref) => FigureRepository(ref.watch(apiClientProvider)),
);
