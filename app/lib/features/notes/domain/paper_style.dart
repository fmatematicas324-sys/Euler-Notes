/// Papel de fondo de una nota. `id` es el valor que guarda el backend; uno
/// desconocido se muestra como [blank].
enum PaperStyle {
  blank('blank', 'Blanco'),
  ruled('ruled', 'Renglonado'),
  grid('grid', 'Milimetrado'),
  dots('dots', 'Punteado'),
  semilog('semilog', 'Semilogarítmico');

  const PaperStyle(this.id, this.label);

  final String id;
  final String label;

  static PaperStyle fromId(String? id) =>
      values.firstWhere((paper) => paper.id == id, orElse: () => blank);
}
