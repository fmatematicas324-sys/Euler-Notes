import 'stroke.dart';

/// Dibujo a mano de una nota (bloque ```ink).
class Drawing {
  const Drawing({
    required this.id,
    required this.noteId,
    required this.width,
    required this.height,
    required this.strokes,
  });

  factory Drawing.fromJson(Map<String, dynamic> json) => Drawing(
    id: json['id'] as int,
    noteId: json['note_id'] as int,
    width: (json['width'] as num).toDouble(),
    height: (json['height'] as num).toDouble(),
    strokes: [
      for (final s in json['strokes'] as List<dynamic>)
        Stroke.fromJson(s as Map<String, dynamic>),
    ],
  );

  final int id;
  final int noteId;

  /// Tamaño del lienzo en sus propias unidades.
  final double width;
  final double height;
  final List<Stroke> strokes;
}
