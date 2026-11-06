import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../domain/backup_format.dart';

/// Resultado de verificar un archivo de copia.
class BackupVerification {
  BackupVerification({
    required this.schemaVersion,
    required this.formatVersion,
    required this.createdAt,
    required this.counts,
    required this.bytes,
    required this.sha256,
    required this.warnings,
    required this.ids,
  });

  final int schemaVersion;
  final int formatVersion;
  final DateTime createdAt;
  final Map<String, int> counts;
  final int bytes;

  /// SHA-256 del archivo completo.
  final String sha256;
  final List<String> warnings;

  /// Ids por tabla, en el orden del archivo.
  final Map<String, List<String>> ids;
}

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
final _inkStart = RegExp(r'^\s*```\s*ink\s*$');
final _blockEnd = RegExp(r'^\s*```\s*$');
final _inkId = RegExp(r'^\s*id\s*:\s*(\S+)\s*$');

/// Ids de dibujo de los bloques ` ```ink ` de [markdown] (en la copia local
/// son UUID).
List<String> inkReferences(String markdown) {
  final ids = <String>[];
  var inside = false;
  for (final line in const LineSplitter().convert(markdown)) {
    if (!inside) {
      inside = _inkStart.hasMatch(line);
    } else if (_blockEnd.hasMatch(line)) {
      inside = false;
    } else if (_inkId.firstMatch(line) case final match?) {
      ids.add(match[1]!);
    }
  }
  return ids;
}

BackupException _invalid(String why) =>
    BackupException('verify_failed', 'La copia no es válida: $why');

/// Lee [file] completo y comprueba, sin modificarlo:
///
/// - cabecera reconocida (formato y versión);
/// - pie presente (si falta, el archivo está incompleto);
/// - SHA-256 del pie igual al de los bytes anteriores;
/// - conteos del pie iguales a las filas leídas;
/// - ids presentes y sin duplicar en cada tabla;
/// - relaciones completas (cada nota tiene su cuaderno y cada dibujo su nota).
///
/// Lanza [BackupException] (`verify_failed`) en cuanto algo no cuadra. Los
/// mensajes nunca incluyen contenido de las notas.
Future<BackupVerification> verifyBackupFile(File file) async {
  // 1) Hash y tamaño del archivo completo, y que termine en salto de línea.
  var bytes = 0;
  var lastByte = -1;
  final fileDigest = Completer<Digest>();
  final fileHasher = sha256.startChunkedConversion(
    _DigestSink(fileDigest.complete),
  );
  try {
    await for (final chunk in file.openRead()) {
      if (chunk.isEmpty) continue;
      bytes += chunk.length;
      lastByte = chunk.last;
      fileHasher.add(chunk);
    }
  } on FileSystemException {
    throw _invalid('no se pudo leer el archivo');
  }
  fileHasher.close();
  final fileSha = (await fileDigest.future).toString();
  if (bytes == 0) throw _invalid('el archivo está vacío');
  if (lastByte != 0x0a) throw _invalid('el archivo está incompleto');

  // 2) Recorrido línea a línea. Cada línea se suma al hash del cuerpo cuando
  //    llega la siguiente: así la última (el pie) queda fuera.
  final bodyDigest = Completer<Digest>();
  final bodyHasher = sha256.startChunkedConversion(
    _DigestSink(bodyDigest.complete),
  );
  Map<String, dynamic>? header;
  String? pending;
  var lineNumber = 0;
  final ids = {for (final t in backupTables) t: <String>[]};
  final seen = {for (final t in backupTables) t: <String>{}};
  final parents = <String, List<(String, String)>>{}; // tabla → (id, padre)
  final inkRefs = <String>[];
  final warnings = <String>[];

  Map<String, dynamic> decode(String line) {
    try {
      final value = jsonDecode(line);
      if (value is Map<String, dynamic>) return value;
    } on FormatException {
      // se informa abajo
    }
    throw _invalid('la línea $lineNumber no es JSON válido');
  }

  void process(String line) {
    final object = decode(line);
    if (header == null) {
      if (object['kind'] != 'header' || object['format'] != backupFormatId) {
        throw _invalid('no es una copia de Euler Notes');
      }
      final version = object['formatVersion'];
      if (version is! int || version < 1 || version > backupFormatVersion) {
        throw _invalid('versión de formato no compatible ($version)');
      }
      header = object;
      return;
    }
    if (object['kind'] != 'row') {
      throw _invalid('línea $lineNumber inesperada');
    }
    final table = object['table'];
    final data = object['data'];
    if (table is! String || !ids.containsKey(table) || data is! Map) {
      throw _invalid('fila $lineNumber mal formada');
    }
    final id = data['id'];
    if (id is! String || id.isEmpty) {
      throw _invalid('fila $lineNumber sin id');
    }
    if (!seen[table]!.add(id)) {
      throw _invalid('id duplicado en $table');
    }
    if (!_uuid.hasMatch(id)) {
      warnings.add('Un id de $table no tiene formato UUID');
    }
    ids[table]!.add(id);
    if (backupRelations[table] case (final column, _)) {
      final parent = data[column];
      if (parent is! String) throw _invalid('fila $lineNumber sin $column');
      (parents[table] ??= []).add((id, parent));
    }
    if (table == 'notes' && data['content'] is String) {
      inkRefs.addAll(inkReferences(data['content'] as String));
    }
  }

  try {
    await for (final line
        in file
            .openRead()
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      lineNumber++;
      if (pending != null) {
        bodyHasher.add(utf8.encode('$pending\n'));
        process(pending);
      }
      pending = line;
    }
  } on FormatException {
    throw _invalid('el archivo no es texto UTF-8');
  } on FileSystemException {
    throw _invalid('no se pudo leer el archivo');
  }
  bodyHasher.close();
  final bodySha = (await bodyDigest.future).toString();

  // 3) Pie.
  if (header == null || pending == null) {
    throw _invalid('el archivo está incompleto');
  }
  final footer = decode(pending);
  if (footer['kind'] != 'footer') {
    throw _invalid('el archivo está incompleto (falta el pie)');
  }
  if (footer['sha256'] != bodySha) {
    throw _invalid('la suma SHA-256 no coincide (archivo dañado)');
  }
  final counts = {for (final t in backupTables) t: ids[t]!.length};
  final footerCounts = footer['counts'];
  if (footerCounts is! Map ||
      backupTables.any((t) => footerCounts[t] != counts[t]) ||
      footer['rows'] != counts.values.fold<int>(0, (a, b) => a + b)) {
    throw _invalid('el número de filas no coincide con el pie');
  }

  // 4) Relaciones.
  for (final MapEntry(key: table, value: (column, parentTable))
      in backupRelations.entries) {
    for (final (_, parent) in parents[table] ?? const <(String, String)>[]) {
      if (!seen[parentTable]!.contains(parent)) {
        throw _invalid('una fila de $table apunta a $column inexistente');
      }
    }
  }
  final missingInk = inkRefs.where((r) => !seen['drawings']!.contains(r));
  if (missingInk.isNotEmpty) {
    warnings.add(
      '${missingInk.length} bloque(s) de tinta apuntan a un dibujo que no '
      'existe (ya faltaba en la base local)',
    );
  }

  final schema = header!['schemaVersion'];
  final created = DateTime.tryParse('${header!['createdAt']}');
  if (schema is! int || created == null) {
    throw _invalid('cabecera incompleta');
  }
  return BackupVerification(
    schemaVersion: schema,
    formatVersion: header!['formatVersion'] as int,
    createdAt: created,
    counts: counts,
    bytes: bytes,
    sha256: fileSha,
    warnings: warnings,
    ids: ids,
  );
}

/// Recibe el único [Digest] que produce `sha256.startChunkedConversion`.
class _DigestSink implements Sink<Digest> {
  _DigestSink(this._onDigest);

  final void Function(Digest) _onDigest;

  @override
  void add(Digest data) => _onDigest(data);

  @override
  void close() {}
}
