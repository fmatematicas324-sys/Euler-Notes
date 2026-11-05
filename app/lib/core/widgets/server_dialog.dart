import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api_client.dart';
import '../api_exception.dart';
import '../server_settings.dart';

/// Diálogo para elegir el servidor (backend) al que se conecta la app.
Future<void> showServerDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _ServerDialog());

class _ServerDialog extends ConsumerStatefulWidget {
  const _ServerDialog();

  @override
  ConsumerState<_ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends ConsumerState<_ServerDialog> {
  late final _url = TextEditingController(text: ref.read(serverUrlProvider));
  late final _token = TextEditingController(
    text: ref.read(serverTokenProvider),
  );
  bool _showToken = false;
  String? _error;
  String? _result;
  bool _testing = false;

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    final String url;
    try {
      url = normalizeServerUrl(_url.text);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    setState(() {
      _testing = true;
      _error = null;
      _result = null;
    });
    try {
      final api = ApiClient(
        ref.read(httpClientProvider),
        baseUrl: url,
        token: _token.text.trim(),
      );
      final body = await api.get('/health', timeout: api.timeouts.health);
      final version = (body as Map<String, dynamic>)['version'];
      // /health es público: /auth/check confirma además que el token es válido.
      await api.get('/auth/check', timeout: api.timeouts.health);
      if (mounted) {
        setState(() => _result = 'Conectado y autenticado: backend v$version');
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    try {
      await ref.read(serverUrlProvider.notifier).change(_url.text);
      await ref.read(serverTokenProvider.notifier).change(_token.text);
      if (mounted) Navigator.of(context).pop();
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Servidor'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('server-url'),
              controller: _url,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Dirección del backend',
                helperText:
                    'En una tablet: la IP del PC con el backend, '
                    'p. ej. http://192.168.1.20:8000',
                helperMaxLines: 2,
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('server-token'),
              controller: _token,
              obscureText: !_showToken,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Token de acceso',
                helperText:
                    'Está en el PC, en backend/data/api_token. '
                    'Sin HTTPS viaja sin cifrar por la WiFi.',
                helperMaxLines: 2,
                suffixIcon: IconButton(
                  tooltip: _showToken ? 'Ocultar token' : 'Mostrar token',
                  icon: Icon(
                    _showToken ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () => setState(() => _showToken = !_showToken),
                ),
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 12),
            if (_result != null)
              Text(_result!, style: TextStyle(color: colors.primary)),
            if (_error != null)
              Text(_error!, style: TextStyle(color: colors.error)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _testing ? null : _test,
          child: const Text('Probar conexión'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _save, child: const Text('Guardar')),
      ],
    );
  }
}
