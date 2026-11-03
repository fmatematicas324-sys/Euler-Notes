import 'package:flutter/material.dart';

import '../api_exception.dart';

void showErrorSnackBar(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(errorMessage(error))));
}

/// Ejecuta una acción y, si falla, muestra el error en un SnackBar.
/// Devuelve `true` si terminó bien.
Future<bool> runGuarded(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
    return true;
  } on Object catch (error) {
    if (context.mounted) showErrorSnackBar(context, error);
    return false;
  }
}
