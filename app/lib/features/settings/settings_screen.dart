import 'package:flutter/material.dart';

import '../backup/presentation/backup_screen.dart';

/// Configuración de la app. Por ahora solo la sección «Datos» (Misión 017).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Datos',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          ListTile(
            key: const Key('settings-backup'),
            leading: const Icon(Icons.save_alt_outlined),
            title: const Text('Copia de seguridad'),
            subtitle: const Text(
              'Guarda tus cuadernos, notas y dibujos en un archivo',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const BackupScreen()),
            ),
          ),
        ],
      ),
    );
  }
}
