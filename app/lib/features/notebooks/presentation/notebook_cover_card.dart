import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../domain/notebook.dart';
import 'cover_art.dart';

enum NotebookAction { rename, changeCover, delete }

/// Cuaderno en la estantería: portada ilustrada con lomo, etiqueta y repisa.
class NotebookCoverCard extends StatelessWidget {
  const NotebookCoverCard({
    super.key,
    required this.notebook,
    required this.onOpen,
    required this.onAction,
  });

  final Notebook notebook;
  final VoidCallback onOpen;
  final ValueChanged<NotebookAction> onAction;

  static const borderRadius = BorderRadius.only(
    topLeft: Radius.circular(3),
    bottomLeft: Radius.circular(3),
    topRight: Radius.circular(10),
    bottomRight: Radius.circular(10),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Semantics(
            button: true,
            label: 'Cuaderno ${notebook.title}',
            child: Material(
              elevation: 5,
              shadowColor: Colors.black54,
              shape: const RoundedRectangleBorder(borderRadius: borderRadius),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onOpen,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CoverArt(cover: notebook.cover),
                    // Lomo.
                    const Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: 14,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0x66000000), Color(0x00000000)],
                          ),
                        ),
                      ),
                    ),
                    const Positioned(
                      left: 14,
                      top: 0,
                      bottom: 0,
                      width: 1,
                      child: ColoredBox(color: Color(0x26FFFFFF)),
                    ),
                    // Etiqueta con el título.
                    Positioned(
                      left: 22,
                      right: 12,
                      bottom: 14,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xF2FFFDF7),
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: const [
                            BoxShadow(color: Color(0x40000000), blurRadius: 4),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                notebook.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: const Color(0xFF1B1F24),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                formatDate(notebook.updatedAt),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: const Color(0xFF5C636A),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: PopupMenuButton<NotebookAction>(
                        tooltip: 'Opciones',
                        iconColor: Colors.white,
                        onSelected: onAction,
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: NotebookAction.rename,
                            child: ListTile(
                              leading: Icon(Icons.edit),
                              title: Text('Renombrar'),
                            ),
                          ),
                          PopupMenuItem(
                            value: NotebookAction.changeCover,
                            child: ListTile(
                              leading: Icon(Icons.palette_outlined),
                              title: Text('Cambiar portada'),
                            ),
                          ),
                          PopupMenuItem(
                            value: NotebookAction.delete,
                            child: ListTile(
                              leading: Icon(Icons.delete_outline),
                              title: Text('Eliminar'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Repisa.
        Container(
          height: 9,
          margin: const EdgeInsets.only(top: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFA1887F), Color(0xFF6D4C41)],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 4,
                offset: Offset(0, 3),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
