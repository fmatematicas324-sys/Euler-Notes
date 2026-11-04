import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../domain/plot_spec.dart';

/// Pide gráficas a `POST /plot` y guarda las últimas en memoria: la vista previa
/// se reconstruye en cada pulsación y no debe volver a pedir la misma imagen.
class PlotRepository {
  PlotRepository(this._api);

  static const cacheSize = 32;

  final ApiClient _api;
  final _cache = <String, Uint8List>{}; // orden de inserción = LRU

  Future<Uint8List> render(
    PlotSpec spec, {
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
    final key = jsonEncode(body);
    final cached = _cache.remove(key);
    if (cached != null) return _cache[key] = cached;

    final png = await _api.postForBytes('/plot', body);
    _cache[key] = png;
    if (_cache.length > cacheSize) _cache.remove(_cache.keys.first);
    return png;
  }
}

final plotRepositoryProvider = Provider<PlotRepository>(
  (ref) => PlotRepository(ref.watch(apiClientProvider)),
);
