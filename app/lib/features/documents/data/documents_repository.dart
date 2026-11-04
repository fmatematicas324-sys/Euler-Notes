import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../domain/library_document.dart';

class DocumentsRepository {
  DocumentsRepository(this._api);

  final ApiClient _api;
  final _files = <int, Uint8List>{};

  Future<List<LibraryDocument>> list() async {
    final body = await _api.get('/documents') as List<dynamic>;
    return [
      for (final item in body)
        LibraryDocument.fromJson(item as Map<String, dynamic>),
    ];
  }

  Future<LibraryDocument> upload(Uint8List bytes, String filename) async =>
      LibraryDocument.fromJson(
        await _api.postBinary(
          '/documents',
          bytes,
          contentType: 'application/pdf',
          query: {'filename': filename},
        ) as Map<String, dynamic>,
      );

  /// Contenido del PDF (se guarda en memoria: el visor puede reconstruirse).
  Future<Uint8List> file(int id) async =>
      _files[id] ??= await _api.getBytes('/documents/$id/file');

  Future<PageText> pageText(int id, int page) async => PageText.fromJson(
    await _api.get('/documents/$id/pages/$page/text') as Map<String, dynamic>,
  );

  Future<void> delete(int id) async {
    await _api.delete('/documents/$id');
    _files.remove(id);
  }
}

final documentsRepositoryProvider = Provider<DocumentsRepository>(
  (ref) => DocumentsRepository(ref.watch(apiClientProvider)),
);

/// Archivo elegido por el usuario.
typedef PickedPdf = ({String name, Uint8List bytes});

/// Selector de archivos del sistema (Web, Linux, Android). Se sustituye en tests.
final pdfPickerProvider = Provider<Future<PickedPdf?> Function()>(
  (ref) => () async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'PDF',
          extensions: ['pdf'],
          mimeTypes: ['application/pdf'],
          uniformTypeIdentifiers: ['com.adobe.pdf'],
        ),
      ],
    );
    if (file == null) return null;
    return (name: file.name, bytes: await file.readAsBytes());
  },
);
