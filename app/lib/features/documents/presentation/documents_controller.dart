import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/documents_repository.dart';
import '../domain/library_document.dart';

/// Biblioteca de PDF (más recientes primero).
class DocumentsController extends AsyncNotifier<List<LibraryDocument>> {
  DocumentsRepository get _repository => ref.read(documentsRepositoryProvider);

  @override
  Future<List<LibraryDocument>> build() =>
      ref.watch(documentsRepositoryProvider).list();

  Future<LibraryDocument> upload(PickedPdf file) async {
    final document = await _repository.upload(file.bytes, file.name);
    ref.invalidateSelf();
    await future;
    return document;
  }

  Future<void> delete(int id) async {
    await _repository.delete(id);
    ref.invalidateSelf();
    await future;
  }
}

final documentsControllerProvider =
    AsyncNotifierProvider<DocumentsController, List<LibraryDocument>>(
      DocumentsController.new,
      retry: (_, _) => null,
    );
