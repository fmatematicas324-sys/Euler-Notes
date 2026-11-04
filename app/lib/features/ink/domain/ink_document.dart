import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'stroke.dart';

/// Trazos de un dibujo con deshacer/rehacer. [revision] aumenta con cada
/// cambio (sirve para invalidar cachés y para el autoguardado).
class InkDocument extends ChangeNotifier {
  InkDocument([List<Stroke> strokes = const []]) : _strokes = [...strokes];

  final List<Stroke> _strokes;
  final _undo = <_Change>[];
  final _redo = <_Change>[];
  int _revision = 0;

  List<Stroke> get strokes => List.unmodifiable(_strokes);
  int get revision => _revision;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void add(Stroke stroke) => _apply(_Change.add([(_strokes.length, stroke)]));

  /// Borra los trazos que pasan a menos de [radius] de [point] (borrador por
  /// trazo). Devuelve si borró alguno.
  bool eraseAt(Offset point, double radius) {
    final hit = [
      for (var i = 0; i < _strokes.length; i++)
        if (_strokes[i].hits(point, radius)) (i, _strokes[i]),
    ];
    if (hit.isEmpty) return false;
    _apply(_Change.remove(hit));
    return true;
  }

  void clear() {
    if (_strokes.isEmpty) return;
    _apply(
      _Change.remove([
        for (var i = 0; i < _strokes.length; i++) (i, _strokes[i]),
      ]),
    );
  }

  void undo() {
    if (_undo.isEmpty) return;
    final change = _undo.removeLast();
    change.revert(_strokes);
    _redo.add(change);
    _changed();
  }

  void redo() {
    if (_redo.isEmpty) return;
    final change = _redo.removeLast();
    change.applyTo(_strokes);
    _undo.add(change);
    _changed();
  }

  void _apply(_Change change) {
    change.applyTo(_strokes);
    _undo.add(change);
    _redo.clear();
    _changed();
  }

  void _changed() {
    _revision++;
    notifyListeners();
  }
}

/// Cambio reversible: añadir o quitar trazos en posiciones concretas.
class _Change {
  _Change.add(this.items) : adds = true;
  _Change.remove(this.items) : adds = false;

  final bool adds;

  /// (posición, trazo), en orden creciente de posición.
  final List<(int, Stroke)> items;

  void applyTo(List<Stroke> strokes) =>
      adds ? _insert(strokes) : _delete(strokes);

  void revert(List<Stroke> strokes) =>
      adds ? _delete(strokes) : _insert(strokes);

  void _insert(List<Stroke> strokes) {
    for (final (index, stroke) in items) {
      strokes.insert(index, stroke);
    }
  }

  void _delete(List<Stroke> strokes) {
    for (final (index, _) in items.reversed) {
      strokes.removeAt(index);
    }
  }
}
