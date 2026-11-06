import 'notebook_cover.dart';

class Notebook {
  const Notebook({
    required this.id,
    required this.title,
    required this.cover,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Notebook.fromJson(Map<String, dynamic> json) => Notebook(
    id: '${json['id']}',
    title: json['title'] as String,
    cover: NotebookCover.fromId(json['cover'] as String?),
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );

  /// Id del servidor (número en texto) o UUID local (Etapa 2).
  final String id;
  final String title;
  final NotebookCover cover;
  final DateTime createdAt;
  final DateTime updatedAt;
}
