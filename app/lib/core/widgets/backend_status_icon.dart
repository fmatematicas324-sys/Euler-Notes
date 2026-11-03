import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend_health.dart';

/// Indicador compacto del estado del backend para la AppBar.
class BackendStatusIcon extends ConsumerWidget {
  const BackendStatusIcon({super.key, this.onRetry});

  /// Acción extra al reintentar (p. ej. recargar la lista de la pantalla).
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(backendHealthProvider)
        .when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          data: (version) => Tooltip(
            message: 'Backend conectado (v$version)',
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Icon(Icons.check_circle, color: Colors.green),
            ),
          ),
          error: (_, _) => IconButton(
            tooltip: 'Backend no disponible. Reintentar',
            icon: Icon(Icons.error, color: Theme.of(context).colorScheme.error),
            onPressed: () {
              ref.invalidate(backendHealthProvider);
              onRetry?.call();
            },
          ),
        );
  }
}
