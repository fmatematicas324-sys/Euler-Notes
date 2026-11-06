import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backup_service.dart';
import '../domain/backup_format.dart';

/// Configuración → Datos → Copia de seguridad (Misión 017).
///
/// Exporta la base local de la tablet (cuadernos, notas y dibujos) a un
/// archivo `.eulernotes` que el usuario guarda donde quiera. No modifica la
/// base. La restauración llegará en otra misión.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _running = false;
  BackupProgress? _progress;
  BackupCancelToken? _cancel;
  BackupSummary? _summary;
  String? _error;
  bool _dismissed = false;

  Future<void> _export() async {
    final cancel = BackupCancelToken();
    setState(() {
      _running = true;
      _progress = null;
      _cancel = cancel;
      _summary = null;
      _error = null;
      _dismissed = false;
    });
    try {
      final summary = await ref
          .read(backupServiceProvider)
          .export(
            cancel: cancel,
            onProgress: (p) {
              if (mounted) setState(() => _progress = p);
            },
          );
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _dismissed = summary == null;
      });
    } on BackupException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      // Sin detalles: el error podría citar contenido.
      if (mounted) setState(() => _error = 'No se pudo exportar la copia');
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _cancel = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Copia de seguridad')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Exportar copia', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Guarda en un archivo todos los cuadernos, notas y dibujos de la '
            'tablet, para conservarlos fuera de la app (p. ej. en Descargas, '
            'una tarjeta SD o la nube). La copia se verifica al terminar y '
            'no cambia nada en la app.',
          ),
          const SizedBox(height: 4),
          Text(
            'No incluye la dirección del servidor ni el token de acceso. '
            'Restaurar una copia llegará en una próxima versión.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton.icon(
                key: const Key('backup-export'),
                onPressed: _running ? null : _export,
                icon: const Icon(Icons.save_alt),
                label: const Text('Exportar copia'),
              ),
              if (_running && _cancel != null) ...[
                const SizedBox(width: 12),
                TextButton(
                  key: const Key('backup-cancel'),
                  onPressed: () => setState(() => _cancel!.cancel()),
                  child: const Text('Cancelar'),
                ),
              ],
            ],
          ),
          if (_running) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(
              key: const Key('backup-progress'),
              value: _progress?.fraction,
            ),
            const SizedBox(height: 8),
            Text(_progress?.phase.label ?? 'Preparando…'),
          ],
          if (!_running && _summary != null) ...[
            const SizedBox(height: 16),
            _ResultCard.success(_summary!),
          ],
          if (!_running && _error != null) ...[
            const SizedBox(height: 16),
            _ResultCard.failure(_error!),
          ],
          if (!_running && _dismissed)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Text('No se eligió dónde guardar: no se exportó nada.'),
            ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard.success(BackupSummary this.summary) : error = null;
  const _ResultCard.failure(String this.error) : summary = null;

  final BackupSummary? summary;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final s = summary;
    if (s == null) {
      return Card(
        key: const Key('backup-failed'),
        color: colors.errorContainer,
        child: ListTile(
          leading: Icon(Icons.error_outline, color: colors.onErrorContainer),
          title: const Text('La copia no se completó'),
          subtitle: Text(
            '$error\nNo quedó ningún archivo a medias y tus datos no '
            'cambiaron.',
          ),
        ),
      );
    }
    final kib = (s.bytes / 1024).toStringAsFixed(1);
    return Card(
      key: const Key('backup-done'),
      child: ListTile(
        leading: Icon(Icons.verified_outlined, color: colors.primary),
        title: const Text('Copia completada y verificada'),
        subtitle: Text(
          '${s.counts['notebooks']} cuadernos · ${s.counts['notes']} notas · '
          '${s.counts['drawings']} dibujos · $kib KiB\n'
          'Esquema ${s.schemaVersion} · SHA-256 ${s.sha256.substring(0, 12)}…'
          '${s.warnings.isEmpty ? '' : '\nAvisos: ${s.warnings.join('; ')}'}',
        ),
      ),
    );
  }
}
