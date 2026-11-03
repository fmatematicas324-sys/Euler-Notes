import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend_health.dart';

/// Pantalla inicial de v0.1. La lista de cuadernos se añadirá aquí.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cuaderno Científico')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.menu_book_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Tus cuadernos aparecerán aquí',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 24),
              const BackendStatus(),
            ],
          ),
        ),
      ),
    );
  }
}

class BackendStatus extends ConsumerWidget {
  const BackendStatus({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(backendHealthProvider);
    return health.when(
      loading: () => const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text('Conectando con el backend…'),
        ],
      ),
      data: (version) => Chip(
        avatar: const Icon(Icons.check_circle, color: Colors.green),
        label: Text('Backend conectado (v$version)'),
      ),
      error: (error, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Chip(
            avatar: Icon(Icons.error_outline, color: Colors.red),
            label: Text('Backend no disponible'),
          ),
          TextButton.icon(
            onPressed: () => ref.invalidate(backendHealthProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}
