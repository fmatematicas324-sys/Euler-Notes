String _two(int n) => n.toString().padLeft(2, '0');

/// Fecha local en formato `dd/MM/aaaa`.
String formatDate(DateTime value) {
  final local = value.toLocal();
  return '${_two(local.day)}/${_two(local.month)}/${local.year}';
}

/// Fecha y hora local en formato `dd/MM/aaaa HH:mm`.
String formatDateTime(DateTime value) {
  final local = value.toLocal();
  return '${_two(local.day)}/${_two(local.month)}/${local.year} '
      '${_two(local.hour)}:${_two(local.minute)}';
}

/// Tamaño legible: `850 B`, `12,4 KB`, `3,1 MB`.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1).replaceAll('.', ',')} KB';
  return '${(kb / 1024).toStringAsFixed(1).replaceAll('.', ',')} MB';
}
