// Comprueba la configuración de copias de seguridad de Android (M3): el token
// de acceso (FlutterSharedPreferences.xml) no debe salir del dispositivo, y no
// se excluye nada más. Lee los archivos del proyecto (cwd = app/).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _main = 'android/app/src/main';
const _prefsExclude =
    '<exclude domain="sharedpref" path="FlutterSharedPreferences.xml" />';

String _read(String path) => File('$_main/$path').readAsStringSync();

/// Contenido de [tag] (`<tag>...</tag>`) dentro de [xml], o `null`.
String? _section(String xml, String tag) =>
    RegExp('<$tag>(.*?)</$tag>', dotAll: true).firstMatch(xml)?.group(1);

/// Elimina los comentarios XML para analizar solo las reglas efectivas.
String _withoutComments(String xml) =>
    xml.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

void main() {
  final manifest = _withoutComments(_read('AndroidManifest.xml'));

  test('el manifiesto enlaza las reglas para Android 6–11 y 12+', () {
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
  });

  test('no se desactiva la copia de seguridad del resto de datos', () {
    expect(manifest, isNot(contains('android:allowBackup="false"')));
  });

  test('Android 6–11: se excluye solo el archivo del token', () {
    final rules = _withoutComments(_read('res/xml/backup_rules.xml'));
    final body = _section(rules, 'full-backup-content')!;
    expect(body, contains(_prefsExclude));
    expect(RegExp('<exclude ').allMatches(body), hasLength(1));
    // Un <include> convertiría las reglas en lista blanca y dejaría fuera
    // datos de usuario que sí deben respaldarse.
    expect(body, isNot(contains('<include')));
  });

  test('Android 12+: excluido de la nube y de la transferencia', () {
    final rules = _withoutComments(_read('res/xml/data_extraction_rules.xml'));
    for (final tag in ['cloud-backup', 'device-transfer']) {
      final body = _section(rules, tag);
      expect(body, isNotNull, reason: tag);
      expect(body, contains(_prefsExclude), reason: tag);
      expect(RegExp('<exclude ').allMatches(body!), hasLength(1), reason: tag);
      expect(body, isNot(contains('<include')), reason: tag);
    }
  });

  test('las preferencias excluidas solo guardan ajustes y borradores', () {
    // Si se añaden más claves a shared_preferences, revisar si deben
    // respaldarse (y moverlas a otro almacén si es así).
    final source = File('lib/core/server_settings.dart').readAsStringSync();
    final keys = RegExp(r"const _\w+Key = '([^']+)';")
        .allMatches(source)
        .map((m) => m.group(1))
        .toSet();
    expect(keys, {'server_url', 'server_token', 'offline_mode'});
    final writers = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where(
          (f) =>
              RegExp(r'\.set(String|Bool|Int|Double|StringList)\(')
                  .hasMatch(f.readAsStringSync()),
        )
        .map((f) => f.path.replaceAll(r'\', '/'))
        .toList();
    // Borradores de notas (Misión 013, ADR 21): son temporales (la nota real
    // está en el servidor) y no deben salir del dispositivo, así que se
    // quedan en este archivo excluido de las copias de seguridad.
    expect(
      writers,
      unorderedEquals([
        'lib/core/server_settings.dart',
        'lib/features/notes/data/note_drafts.dart',
      ]),
    );
  });
}
