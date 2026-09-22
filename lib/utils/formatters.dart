String formatBytes(int? bytes) {
  if (bytes == null) return '—';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  double size = bytes.toDouble();
  var unitIndex = 0;
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex++;
  }
  final formatted = unitIndex == 0 ? size.toStringAsFixed(0) : size.toStringAsFixed(1);
  return '$formatted ${units[unitIndex]}';
}

String formatDate(DateTime? date) {
  if (date == null) return '';
  final local = date.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
