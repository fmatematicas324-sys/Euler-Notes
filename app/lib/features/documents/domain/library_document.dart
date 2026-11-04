/// PDF importado en la biblioteca del backend.
class LibraryDocument {
  const LibraryDocument({
    required this.id,
    required this.filename,
    required this.size,
    required this.pages,
    required this.createdAt,
  });

  factory LibraryDocument.fromJson(Map<String, dynamic> json) =>
      LibraryDocument(
        id: json['id'] as int,
        filename: json['filename'] as String,
        size: json['size'] as int,
        pages: json['pages'] as int,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final int id;
  final String filename;
  final int size;
  final int pages;
  final DateTime createdAt;
}

/// Texto extraído de una página y su conversión aproximada a LaTeX.
class PageText {
  const PageText({required this.page, required this.text, required this.latex});

  factory PageText.fromJson(Map<String, dynamic> json) => PageText(
    page: json['page'] as int,
    text: json['text'] as String,
    latex: json['latex'] as String,
  );

  final int page;
  final String text;
  final String latex;
}
