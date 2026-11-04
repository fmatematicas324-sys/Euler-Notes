/// Portadas de cuaderno. `id` es el valor que guarda el backend; uno
/// desconocido (de una versión futura) se muestra como [classic].
///
/// Las portadas de homenaje evocan la obra de cada científico (sin retratos).
enum NotebookCover {
  classic('classic', 'Clásica'),
  physics('physics', 'Física'),
  calculus('calculus', 'Cálculo'),
  astronomy('astronomy', 'Astronomía'),
  chemistry('chemistry', 'Química'),
  einstein('einstein', 'Homenaje a Einstein'),
  curie('curie', 'Homenaje a Marie Curie'),
  sagan('sagan', 'Homenaje a Carl Sagan');

  const NotebookCover(this.id, this.label);

  final String id;
  final String label;

  static NotebookCover fromId(String? id) =>
      values.firstWhere((cover) => cover.id == id, orElse: () => classic);
}
