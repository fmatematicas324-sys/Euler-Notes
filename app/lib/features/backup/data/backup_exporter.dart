import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../../core/local_db/local_database.dart';
import '../domain/backup_format.dart';
import 'backup_verifier.dart';

/// Destino de bytes del exportador. Existe para poder simular errores de
/// escritura en las pruebas.
abstract class BackupWriter {
  Future<void> write(List<int> bytes);

  /// Vuelca al disco (`fsync`) y cierra.
  Future<void> close();

  /// Cierra sin garantías, tras un error.
  Future<void> abort();
}

/// [BackupWriter] sobre un archivo, con un búfer de 64 KiB.
class FileBackupWriter implements BackupWriter {
  FileBackupWriter._(this._file);

  static Future<FileBackupWriter> open(File file) async =>
      FileBackupWriter._(await file.open(mode: FileMode.writeOnly));

  final RandomAccessFile _file;
  final _buffer = BytesBuilder(copy: false);

  @override
  Future<void> write(List<int> bytes) async {
    _buffer.add(bytes);
    if (_buffer.length >= 64 * 1024) await _file.writeFrom(_buffer.takeBytes());
  }

  @override
  Future<void> close() async {
    if (_buffer.isNotEmpty) await _file.writeFrom(_buffer.takeBytes());
    await _file.flush(); // fsync
    await _file.close();
  }

  @override
  Future<void> abort() async {
    try {
      await _file.close();
    } on FileSystemException {
      // ya estaba cerrado o el disco falló: no hay nada más que hacer
    }
  }
}

typedef BackupWriterFactory = Future<BackupWriter> Function(File file);

/// Pone [partial] en el lugar de [destination]. Por defecto `rename`, que en
/// un mismo sistema de archivos es atómico: si ya existía una copia con ese
/// nombre, se sustituye entera en un solo paso, o no se toca.
typedef BackupReplacer = Future<void> Function(
  File partial,
  String destination,
);

Future<void> _renameInto(File partial, String destination) async {
  await partial.rename(destination);
}

/// Quita usuario, contraseña, consulta y fragmento de la URL de origen
/// (columna `source`). Normalmente no llevan nada de eso; así ninguna
/// credencial puede acabar en una copia.
String sanitizeSourceUrl(String source) {
  final uri = Uri.tryParse(source);
  if (uri == null || !uri.hasAuthority) return source;
  if (uri.userInfo.isEmpty && !uri.hasQuery && !uri.hasFragment) return source;
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
  ).toString();
}

/// Exporta la base local a un archivo de copia (formato en
/// `backup_format.dart` y `docs/BACKUP_FORMAT.md`).
///
/// Garantías:
/// - **Solo lee** la base: no escribe ni borra nada en ella.
/// - Lee todas las tablas dentro de una transacción de lectura: la copia es
///   una foto coherente aunque la app guarde algo a la vez.
/// - Escribe en `<destino>.partial` y solo al final, tras verificarlo, lo
///   renombra al destino (reemplazo atómico). Si algo falla o se cancela,
///   borra el `.partial` y el destino —por ejemplo, una copia anterior con
///   el mismo nombre— queda intacto.
/// - No registra nada en los logs.
class BackupExporter {
  BackupExporter(
    this._db, {
    required this.appVersion,
    DateTime Function()? clock,
    BackupWriterFactory? openWriter,
    BackupReplacer? replace,
  }) : _clock = clock ?? DateTime.now,
       _openWriter = openWriter ?? FileBackupWriter.open,
       _replace = replace ?? _renameInto;

  final LocalDatabase _db;
  final String appVersion;
  final DateTime Function() _clock;
  final BackupWriterFactory _openWriter;
  final BackupReplacer _replace;

  Future<BackupSummary> exportTo(
    File destination, {
    BackupProgressCallback? onProgress,
    BackupCancelToken? cancel,
  }) async {
    final token = cancel ?? BackupCancelToken();
    void report(BackupPhase phase, [double? fraction]) =>
        onProgress?.call(BackupProgress(phase, fraction));

    report(BackupPhase.reading);
    final snapshot = await _readSnapshot();
    token.throwIfCancelled();

    final partial = File('${destination.path}.partial');
    final createdAt = _clock().toUtc();
    BackupWriter? writer;
    String fileSha;
    var bytes = 0;
    try {
      if (await partial.exists()) await partial.delete();
      writer = await _openWriter(partial);

      final fileDigest = Completer<Digest>();
      final bodyDigest = Completer<Digest>();
      final fileHasher = sha256.startChunkedConversion(
        _Once(fileDigest.complete),
      );
      final bodyHasher = sha256.startChunkedConversion(
        _Once(bodyDigest.complete),
      );
      Future<void> line(Object json, {bool body = true}) async {
        final encoded = utf8.encode('${jsonEncode(json)}\n');
        if (body) bodyHasher.add(encoded);
        fileHasher.add(encoded);
        bytes += encoded.length;
        await writer!.write(encoded);
      }

      await line({
        'kind': 'header',
        'format': backupFormatId,
        'formatVersion': backupFormatVersion,
        'createdAt': createdAt.toIso8601String(),
        'app': 'Euler Notes',
        'appVersion': appVersion,
        'schemaVersion': snapshot.schemaVersion,
        'tables': {
          for (final t in backupTables) t: {'columns': snapshot.columns[t]},
        },
      });

      final total = snapshot.rows.values.fold<int>(0, (a, r) => a + r.length);
      var written = 0;
      report(BackupPhase.writing, total == 0 ? 1 : 0);
      for (final table in backupTables) {
        for (final row in snapshot.rows[table]!) {
          token.throwIfCancelled();
          await line({'kind': 'row', 'table': table, 'data': row});
          written++;
          if (written % 50 == 0 || written == total) {
            report(BackupPhase.writing, written / total);
          }
        }
      }

      bodyHasher.close();
      await line({
        'kind': 'footer',
        'counts': snapshot.counts,
        'rows': total,
        'sha256': (await bodyDigest.future).toString(),
      }, body: false);
      fileHasher.close();
      fileSha = (await fileDigest.future).toString();

      final w = writer;
      writer = null;
      await w.close();
      token.throwIfCancelled();

      // Verificación: se relee el archivo desde el disco.
      report(BackupPhase.verifying);
      final check = await verifyBackupFile(partial);
      if (check.sha256 != fileSha || check.bytes != bytes) {
        throw const BackupException(
          'verify_failed',
          'La copia escrita no coincide con la generada',
        );
      }
      for (final t in backupTables) {
        if (check.counts[t] != snapshot.counts[t]) {
          throw const BackupException(
            'verify_failed',
            'La copia no tiene las mismas filas que la base local',
          );
        }
      }
      token.throwIfCancelled();

      await _replace(partial, destination.path);
      report(BackupPhase.done, 1);
      return BackupSummary(
        counts: snapshot.counts,
        schemaVersion: snapshot.schemaVersion,
        bytes: bytes,
        sha256: fileSha,
        createdAt: createdAt,
        warnings: check.warnings,
        location: destination.path,
      );
    } on BackupException {
      await _discard(writer, partial);
      rethrow;
    } on FileSystemException {
      await _discard(writer, partial);
      throw const BackupException(
        'write_failed',
        'No se pudo escribir la copia (¿falta espacio o permiso?)',
      );
    } catch (_) {
      await _discard(writer, partial);
      throw const BackupException(
        'write_failed',
        'No se pudo escribir la copia',
      );
    }
  }

  Future<void> _discard(BackupWriter? writer, File partial) async {
    await writer?.abort();
    try {
      if (await partial.exists()) await partial.delete();
    } on FileSystemException {
      // se intentó; el `.partial` nunca se confunde con una copia válida
    }
  }

  /// Lee el esquema y todas las filas en una sola transacción de lectura.
  Future<_Snapshot> _readSnapshot() async {
    return _db.transaction(() async {
      final version = int.parse(await _db.scalar('PRAGMA user_version'));
      if (!supportedSchemaVersions.contains(version)) {
        throw BackupException(
          'unsupported_schema',
          'Esta versión de la app no sabe copiar el esquema $version de la '
              'base local',
        );
      }
      final tables = await _db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name NOT LIKE 'sqlite_%'",
          )
          .get();
      final names = {for (final t in tables) t.read<String>('name')};
      for (final table in backupTables) {
        if (!names.contains(table)) {
          throw BackupException(
            'unsupported_schema',
            'Falta la tabla $table en la base local',
          );
        }
      }
      // Una tabla desconocida con datos se perdería en silencio: mejor parar.
      for (final name in names.difference(backupTables.toSet())) {
        final count = await _db.scalar('SELECT COUNT(*) FROM "$name"');
        if (count != '0') {
          throw BackupException(
            'unknown_table',
            'La base local tiene datos que esta versión no sabe copiar '
                '($name)',
          );
        }
      }

      final columns = <String, List<String>>{};
      final rows = <String, List<Map<String, Object?>>>{};
      for (final table in backupTables) {
        final info = await _db
            .customSelect('PRAGMA table_info("$table")')
            .get();
        columns[table] = [for (final c in info) c.read<String>('name')];
        final result = await _db
            .customSelect('SELECT * FROM "$table" ORDER BY id')
            .get();
        rows[table] = [for (final r in result) _encodeRow(r.data)];
      }
      return _Snapshot(version, columns, rows);
    });
  }

  static Map<String, Object?> _encodeRow(Map<String, Object?> data) => {
    for (final MapEntry(:key, :value) in data.entries)
      key: switch (value) {
        Uint8List() => {'base64': base64Encode(value)},
        String() when key == 'source' => sanitizeSourceUrl(value),
        _ => value,
      },
  };
}

class _Snapshot {
  _Snapshot(this.schemaVersion, this.columns, this.rows);

  final int schemaVersion;
  final Map<String, List<String>> columns;
  final Map<String, List<Map<String, Object?>>> rows;

  Map<String, int> get counts => {
    for (final t in backupTables) t: rows[t]!.length,
  };
}

class _Once implements Sink<Digest> {
  _Once(this._onDigest);

  final void Function(Digest) _onDigest;

  @override
  void add(Digest data) => _onDigest(data);

  @override
  void close() {}
}
