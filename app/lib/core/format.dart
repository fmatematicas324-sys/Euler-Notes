String _two(int n) => n.toString().padLeft(2, '0');

/// Fecha y hora local en formato `dd/MM/aaaa HH:mm`.
String formatDateTime(DateTime value) {
  final local = value.toLocal();
  return '${_two(local.day)}/${_two(local.month)}/${local.year} '
      '${_two(local.hour)}:${_two(local.minute)}';
}
