import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/app_version.dart';
import '../../../core/local_db/local_database.dart';
import '../../../core/local_db/local_database_provider.dart';
import '../domain/backup_format.dart';
import 'backup_exporter.dart';

/// Resultado de copiar el archivo a un documento de Android.
class DocumentCopyReceipt {
  const DocumentCopyReceipt({required this.bytes, required this.sha256});

  final int bytes;

  /// SHA-256 calculado releyendo el documento ya escrito.
  final String sha256;
}

/// Documentos de Android (Storage Access Framework): el usuario elige dónde
/// guardar con el selector del sistema.
abstract class DocumentStore {
  /// Abre el selector «Guardar como». Devuelve la URI o `null` si se cancela.
  Future<String?> create(String suggestedName, String mimeType);

  /// Copia [file] en [uri] y relee el documento para calcular su SHA-256.
  Future<DocumentCopyReceipt> copyFrom(File file, String uri);

  /// Borra el documento (p. ej. si la copia falló). `false` si no pudo.
  Future<bool> delete(String uri);
}

/// [DocumentStore] sobre el canal `dev.eulernotes/backup` de `MainActivity`.
class AndroidDocumentStore implements DocumentStore {
  const AndroidDocumentStore();

  static const _channel = MethodChannel('dev.eulernotes/backup');

  @override
  Future<String?> create(String suggestedName, String mimeType) =>
      _channel.invokeMethod<String>('createDocument', {
        'name': suggestedName,
        'mimeType': mimeType,
      });

  @override
  Future<DocumentCopyReceipt> copyFrom(File file, String uri) async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'copyToDocument',
      {'path': file.path, 'uri': uri},
    );
    return DocumentCopyReceipt(
      bytes: (result?['bytes'] as num?)?.toInt() ?? -1,
      sha256: result?['sha256'] as String? ?? '',
    );
  }

  @override
  Future<bool> delete(String uri) async {
    try {
      return await _channel.invokeMethod<bool>('deleteDocument', {
            'uri': uri,
          }) ??
          false;
    } on PlatformException {
      return false;
    }
  }
}

/// Elige una ruta para guardar en escritorio. `null` si se cancela.
typedef SavePathPicker = Future<String?> Function(String suggestedName);

Future<String?> _desktopSavePath(String suggestedName) async {
  final location = await getSaveLocation(
    suggestedName: suggestedName,
    acceptedTypeGroups: const [
      XTypeGroup(
        label: 'Copia de Euler Notes',
        extensions: [backupFileExtension],
      ),
    ],
  );
  return location?.path;
}

/// Orquesta la exportación completa: elegir destino → generar y verificar →
/// guardar. En Android la copia se genera primero en la carpeta temporal de
/// la app y luego se copia al documento elegido; si algo falla, el documento
/// se borra para no dejar un archivo a medias.
class BackupService {
  BackupService(
    this._db, {
    required this.platform,
    DocumentStore? documents,
    SavePathPicker? pickSavePath,
    Future<Directory> Function()? tempDirectory,
    DateTime Function()? clock,
    this.openWriter,
  }) : _documents = documents ?? const AndroidDocumentStore(),
       _pickSavePath = pickSavePath ?? _desktopSavePath,
       _tempDirectory = tempDirectory ?? getTemporaryDirectory,
       _clock = clock ?? DateTime.now;

  final LocalDatabase _db;
  final BackupPlatform platform;
  final DocumentStore _documents;
  final SavePathPicker _pickSavePath;
  final Future<Directory> Function() _tempDirectory;
  final DateTime Function() _clock;

  /// Solo para pruebas: simula errores de escritura.
  final BackupWriterFactory? openWriter;

  BackupExporter _exporter() => BackupExporter(
    _db,
    appVersion: appVersion,
    clock: _clock,
    openWriter: openWriter,
  );

  /// Exporta la copia. Devuelve `null` si el usuario cancela la elección del
  /// destino; lanza [BackupException] si falla.
  Future<BackupSummary?> export({
    BackupProgressCallback? onProgress,
    BackupCancelToken? cancel,
  }) async {
    final name = suggestedBackupName(_clock());
    onProgress?.call(const BackupProgress(BackupPhase.choosing));
    switch (platform) {
      case BackupPlatform.unsupported:
        throw const BackupException(
          'unsupported_platform',
          'Exportar copias no está disponible en esta plataforma',
        );
      case BackupPlatform.desktop:
        final path = await _pickSavePath(name);
        if (path == null) return null;
        return _exporter().exportTo(
          File(path),
          onProgress: onProgress,
          cancel: cancel,
        );
      case BackupPlatform.android:
        return _exportToDocument(name, onProgress, cancel);
    }
  }

  Future<BackupSummary?> _exportToDocument(
    String name,
    BackupProgressCallback? onProgress,
    BackupCancelToken? cancel,
  ) async {
    final String? uri;
    try {
      uri = await _documents.create(name, backupMimeType);
    } on PlatformException {
      throw const BackupException(
        'copy_failed',
        'No se pudo abrir el selector de archivos',
      );
    }
    if (uri == null) return null;

    Directory? work;
    var saved = false;
    try {
      final temp = await _tempDirectory();
      work = await temp.createTemp('euler-backup-');
      final summary = await _exporter().exportTo(
        File('${work.path}/$name'),
        onProgress: onProgress,
        cancel: cancel,
      );
      cancel?.throwIfCancelled();

      onProgress?.call(const BackupProgress(BackupPhase.copying));
      final DocumentCopyReceipt receipt;
      try {
        receipt = await _documents.copyFrom(File(summary.location!), uri);
      } on PlatformException {
        throw const BackupException(
          'copy_failed',
          'No se pudo escribir en el destino elegido',
        );
      }
      if (receipt.sha256 != summary.sha256 || receipt.bytes != summary.bytes) {
        throw const BackupException(
          'verify_failed',
          'El archivo guardado no coincide con la copia (se ha borrado)',
        );
      }
      saved = true;
      onProgress?.call(const BackupProgress(BackupPhase.done, 1));
      return summary.withLocation(uri);
    } finally {
      if (!saved) await _documents.delete(uri);
      try {
        await work?.delete(recursive: true);
      } on FileSystemException {
        // la carpeta temporal la limpia Android si hace falta
      }
    }
  }
}

enum BackupPlatform { android, desktop, unsupported }

BackupPlatform get currentBackupPlatform {
  if (kIsWeb) return BackupPlatform.unsupported;
  if (Platform.isAndroid) return BackupPlatform.android;
  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    return BackupPlatform.desktop;
  }
  return BackupPlatform.unsupported;
}

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(
    ref.watch(localDatabaseProvider),
    platform: currentBackupPlatform,
  ),
);
