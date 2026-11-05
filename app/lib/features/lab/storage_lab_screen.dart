import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/local_db/local_database.dart';
import 'storage_benchmark.dart';

/// Laboratorio de la Misión 014: mide la base de datos local (Drift + SQLite)
/// en el dispositivo real. Usa una base aparte (`euler_notes_lab`) que se
/// vacía al terminar: no toca las notas.
class StorageLabScreen extends StatefulWidget {
  const StorageLabScreen({super.key});

  @override
  State<StorageLabScreen> createState() => _StorageLabScreenState();
}

class _StorageLabScreenState extends State<StorageLabScreen> {
  List<BenchmarkResult>? _results;
  String? _step;
  Object? _error;
  Duration? _total;

  bool get _running => _step != null;

  Future<void> _run() async {
    setState(() {
      _results = null;
      _error = null;
      _total = null;
      _step = 'Preparando';
    });
    final total = Stopwatch()..start();
    final db = LocalDatabase.open('euler_notes_lab');
    try {
      final results = await runStorageBenchmark(
        db,
        onProgress: (step) {
          if (mounted) setState(() => _step = step);
        },
      );
      total.stop();
      if (mounted) {
        setState(() {
          _results = results;
          _total = total.elapsed;
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      await db.close();
      if (mounted) setState(() => _step = null);
    }
  }

  String get _report {
    final lines = [
      'Euler Notes — laboratorio de almacenamiento (Misión 014)',
      'Plataforma: $defaultTargetPlatform',
      if (_total != null)
        'Duración total: ${(_total!.inMilliseconds / 1000).toStringAsFixed(1)} s',
      ...?_results?.map((r) => r.toString()),
    ];
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Laboratorio: almacenamiento local'),
        actions: [
          if (_results != null)
            IconButton(
              tooltip: 'Copiar resultados',
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _report));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Resultados copiados')),
                  );
                }
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Mide si la base de datos local es lo bastante rápida para que la '
            'tablet funcione sin la compu (Etapa 2). Usa una base de pruebas '
            'aparte que se vacía al terminar: tus notas no se tocan.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          if (kIsWeb)
            const Text('En la versión web no está disponible todavía.')
          else
            FilledButton.icon(
              key: const Key('lab-run'),
              onPressed: _running ? null : _run,
              icon: const Icon(Icons.science_outlined),
              label: Text(_running ? 'Midiendo…' : 'Ejecutar la prueba'),
            ),
          if (_running) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text('$_step…'),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              'La prueba falló: $_error',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
          if (_results case final results?) ...[
            const SizedBox(height: 16),
            if (_total != null)
              Text(
                'Duración total: '
                '${(_total!.inMilliseconds / 1000).toStringAsFixed(1)} s',
                style: theme.textTheme.titleMedium,
              ),
            const SizedBox(height: 8),
            for (final result in results)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(switch (result.ok) {
                  true => Icons.check_circle_outline,
                  false => Icons.error_outline,
                  null => Icons.info_outline,
                }, color: switch (result.ok) {
                  true => Colors.green,
                  false => theme.colorScheme.error,
                  null => theme.colorScheme.outline,
                }),
                title: Text(result.label),
                subtitle: result.detail.isEmpty ? null : Text(result.detail),
                trailing: Text(result.value, style: theme.textTheme.titleSmall),
              ),
            const SizedBox(height: 8),
            Text(
              'Toca el icono de copiar (arriba) y pega los resultados en el '
              'chat, o envía una captura.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
