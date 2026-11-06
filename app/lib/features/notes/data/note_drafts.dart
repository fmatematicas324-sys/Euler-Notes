import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/server_settings.dart';

/// Copia local de una nota con cambios que aún no llegaron al servidor.
///
/// Protege el texto si falla la conexión y después Android cierra la app, se
/// acaba la batería o el usuario sale sin guardar (Misión 013).
@immutable
class NoteDraft {
  const NoteDraft({
    required this.title,
    required this.content,
    required this.base,
    required this.savedAt,
  });

  final String title;
  final String content;

  /// Contenido del servidor sobre el que se escribió el borrador. Si al
  /// recuperarlo el servidor tiene otro, la nota cambió desde otro sitio.
  final String base;
  final DateTime savedAt;

  String toJson() => jsonEncode({
    'title': title,
    'content': content,
    'base': base,
    'saved_at': savedAt.toIso8601String(),
  });

  /// `null` si [raw] no es un borrador válido (p. ej. de otra versión).
  static NoteDraft? fromJson(String raw) {
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return NoteDraft(
        title: data['title'] as String,
        content: data['content'] as String,
        base: data['base'] as String,
        savedAt: DateTime.parse(data['saved_at'] as String),
      );
    } on Object {
      return null;
    }
  }
}

/// Borradores guardados en `shared_preferences`, uno por nota y servidor.
///
/// Comparte el archivo con la dirección y el token, que está **excluido de las
/// copias de seguridad** de Android: los borradores tampoco salen del
/// dispositivo. Sin almacenamiento disponible, no hace nada.
class NoteDrafts {
  NoteDrafts(this._preferences, this._server);

  final SharedPreferences? _preferences;
  final String _server;

  static const _prefix = 'note_draft';

  /// La clave incluye el servidor: el id 3 de un PC no es la nota 3 de otro.
  String _key(String noteId) => '$_prefix|$_server|$noteId';

  NoteDraft? read(String noteId) {
    final raw = _preferences?.getString(_key(noteId));
    return raw == null ? null : NoteDraft.fromJson(raw);
  }

  Future<void> write(String noteId, NoteDraft draft) async {
    await _preferences?.setString(_key(noteId), draft.toJson());
  }

  Future<void> remove(String noteId) async {
    await _preferences?.remove(_key(noteId));
  }
}

final noteDraftsProvider = Provider<NoteDrafts>(
  (ref) => NoteDrafts(
    ref.watch(sharedPreferencesProvider),
    ref.watch(serverUrlProvider),
  ),
);
