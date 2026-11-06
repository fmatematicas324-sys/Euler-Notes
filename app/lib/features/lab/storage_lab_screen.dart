import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/local_db/local_database.dart';
import '../../core/local_db/local_database_provider.dart';
import '../../core/server_settings.dart';
import '../sync/server_import.dart';
import 'storage_benchmark.dart';


/// Laboratorio de la Etapa 2.
///
/// - Misión 014: mide la base de datos local (Drift + SQLite) en el
///   dispositivo real, con una base aparte (`euler_notes_lab`) que se vacía.
/// - Misión 015: copia las notas del servidor a la tablet
///   ([localDatabaseName]).
/// - Misión 016: interruptor del modo sin conexión.
class StorageLabScreen extends ConsumerStatefulWidget {
  const StorageLabScreen({super.key});

  @override
  ConsumerState<StorageLabScreen> createState() => _StorageLabScreenState();
}

class _StorageLabScreenState extends ConsumerState<StorageLabScreen> {
  ImportReport? _import;
  String? _importStep;
  Object? _importError;
  (int, int, int)? _localCounts;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) _refreshCounts();
  }

  Future<void> _refreshCounts() async {
    final db = ref.read(localDatabaseProvider);
    try {
      Future<int> count(String table) async =>
          int.parse(await db.scalar('SELECT count(*) FROM $table'));
      final counts = (
        await count('notebooks'),
        await count('notes'),
        await count('drawings'),
      );
      if (mounted) setState(() => _localCounts = counts);
    } on Object {
      // Sin base local todavía (o no disponible): no se muestran cifras.
    }
  }

  Future<void> _runImport() async {
    setState(() {
      _import = null;
      _importError = null;
      _importStep = 'Preparando';
    });
    final db = ref.read(localDatabaseProvider);
    try {
      final importer = ServerImporter(
        ref.read(apiClientProvider),
        db,
        ref.read(serverUrlProvider),
      );
      final report = await importer.run(
        onProgress: (step) {
          if (mounted) setState(() => _importStep = step);
        },
      );
      if (mounted) setState(() => _import = report);
    } on Object catch (error) {
      if (mounted) setState(() => _importError = error);
    } finally {
      if (mounted) setState(() => _importStep = null);
    }
    await _refreshCounts();
  }
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
          if (!kIsWeb) ...[
            Card(
              child: SwitchListTile(
                key: const Key('offline-mode'),
                secondary: const Icon(Icons.cloud_off_outlined),
                title: const Text('Modo sin conexión (beta)'),
                subtitle: const Text(
                  'Cuadernos, notas y dibujos se abren y guardan en la tablet, '
                  'sin la compu. El cálculo, las figuras y los PDF siguen '
                  'necesitando el servidor. Lo que escribas en este modo no '
                  'se envía al servidor.',
                ),
                value: ref.watch(offlineModeProvider),
                onChanged: (enabled) =>
                    ref.read(offlineModeProvider.notifier).change(enabled),
              ),
            ),
            const SizedBox(height: 24),
          ],
          Text('Copia de tus notas en la tablet', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Copia tus cuadernos, notas y dibujos del servidor a la tablet. '
            'No cambia nada en el servidor y se puede repetir sin duplicar. '
            'Por ahora la app sigue trabajando con el servidor: esta copia es '
            'el primer paso para que funcione sin la compu.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          if (_localCounts case (final nb, final nt, final dr))
            Text('En la tablet: $nb cuadernos, $nt notas, $dr dibujos.'),
          const SizedBox(height: 16),
          if (!kIsWeb)
            FilledButton.icon(
              key: const Key('lab-import'),
              onPressed: _importStep != null ? null : _runImport,
              icon: const Icon(Icons.download_for_offline_outlined),
              label: Text(
                _importStep != null
                    ? 'Importando…'
                    : 'Importar desde el servidor',
              ),
            ),
          if (_importStep != null) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text('$_importStep…'),
          ],
          if (_importError != null) ...[
            const SizedBox(height: 16),
            Text(
              'La importación falló y la copia en la tablet no cambió: '
              '$_importError',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
          if (_import case final report?) ...[
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                report.verified
                    ? Icons.check_circle_outline
                    : Icons.error_outline,
                color: report.verified
                    ? Colors.green
                    : theme.colorScheme.error,
              ),
              title: Text(
                report.verified
                    ? 'Importación verificada'
                    : 'La verificación encontró diferencias',
              ),
              subtitle: Text(
                '${report.notebooks} cuadernos, ${report.notes} notas y '
                '${report.drawings} dibujos '
                '(${report.created} nuevos, ${report.updated} actualizados'
                '${report.kept > 0 ? ', ${report.kept} conservados de la tablet' : ''}) '
                'en ${(report.elapsed.inMilliseconds / 1000).toStringAsFixed(1)} s',
              ),
            ),
            for (final text in [...report.mismatches, ...report.warnings])
              Padding(
                padding: const EdgeInsets.only(left: 40, bottom: 4),
                child: Text('• $text'),
              ),
          ],
          const Divider(height: 48),
          Text('Velocidad de la base local', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
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
