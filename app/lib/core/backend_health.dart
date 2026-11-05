import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// Versión del backend si responde a `/health`; error si no está disponible.
/// Sin reintentos automáticos: la UI ofrece un botón para reintentar.
final backendHealthProvider = FutureProvider<String>((ref) async {
  final api = ref.watch(apiClientProvider);
  final body = await api.get('/health', timeout: api.timeouts.health);
  return (body as Map<String, dynamic>)['version'] as String;
}, retry: (retryCount, error) => null);
