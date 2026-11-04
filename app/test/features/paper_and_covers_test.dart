import 'package:euler_notes/features/notebooks/domain/notebook_cover.dart';
import 'package:euler_notes/features/notebooks/presentation/cover_art.dart';
import 'package:euler_notes/features/notes/domain/paper_style.dart';
import 'package:euler_notes/features/notes/presentation/paper_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ids de portada y papel', () {
    expect(NotebookCover.fromId('curie'), NotebookCover.curie);
    expect(NotebookCover.fromId(null), NotebookCover.classic);
    expect(PaperStyle.fromId('dots'), PaperStyle.dots);
    expect(PaperStyle.fromId('papiro'), PaperStyle.blank);
    // Los ids cumplen el patrón que valida el backend.
    final pattern = RegExp(r'^[a-z][a-z0-9_]{0,31}$');
    for (final id in [
      ...NotebookCover.values.map((c) => c.id),
      ...PaperStyle.values.map((p) => p.id),
    ]) {
      expect(pattern.hasMatch(id), isTrue, reason: id);
    }
  });

  testWidgets('todas las portadas se dibujan en claro y oscuro', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Wrap(
            children: [
              for (final cover in NotebookCover.values)
                SizedBox(
                  width: 140,
                  height: 200,
                  child: CoverArt(cover: cover),
                ),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('todos los papeles se dibujan en claro y oscuro', (tester) async {
    for (final brightness in Brightness.values) {
      for (final paper in PaperStyle.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: PaperBackground(
              style: paper,
              child: const SizedBox(width: 800, height: 600),
            ),
          ),
        );
        expect(tester.takeException(), isNull, reason: '$paper $brightness');
      }
    }
  });

  test('el papel solo se repinta si cambia', () {
    const a = PaperPainter(style: PaperStyle.grid, dark: false);
    expect(
      a.shouldRepaint(const PaperPainter(style: PaperStyle.grid, dark: false)),
      isFalse,
    );
    expect(
      a.shouldRepaint(const PaperPainter(style: PaperStyle.dots, dark: false)),
      isTrue,
    );
    expect(
      a.shouldRepaint(const PaperPainter(style: PaperStyle.grid, dark: true)),
      isTrue,
    );
  });
}
