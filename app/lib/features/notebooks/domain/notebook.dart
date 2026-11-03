class Notebook {
  const Notebook({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Notebook.fromJson(Map<String, dynamic> json) => Notebook(
    id: json['id'] as int,
    title: json['title'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );

  final int id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
}
