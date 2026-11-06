import 'paper_style.dart';

class NoteSummary {
  const NoteSummary({
    required this.id,
    required this.notebookId,
    required this.title,
    required this.updatedAt,
  });

  factory NoteSummary.fromJson(Map<String, dynamic> json) => NoteSummary(
    id: '${json['id']}',
    notebookId: '${json['notebook_id']}',
    title: json['title'] as String,
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );

  /// Id del servidor (número en texto) o UUID local (Etapa 2).
  final String id;
  final String notebookId;
  final String title;
  final DateTime updatedAt;
}

class Note extends NoteSummary {
  const Note({
    required super.id,
    required super.notebookId,
    required super.title,
    required super.updatedAt,
    required this.content,
    this.paper = PaperStyle.blank,
  });

  factory Note.fromJson(Map<String, dynamic> json) => Note(
    id: '${json['id']}',
    notebookId: '${json['notebook_id']}',
    title: json['title'] as String,
    updatedAt: DateTime.parse(json['updated_at'] as String),
    content: json['content'] as String,
    paper: PaperStyle.fromId(json['paper'] as String?),
  );

  /// Markdown con fórmulas LaTeX (`$...$` en línea, `$$...$$` en bloque).
  final String content;

  final PaperStyle paper;
}
