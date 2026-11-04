/// Formatos de fecha y tamaño en español, sin depender de datos de localización
/// cargados (funcionan igual en la app y en las pruebas).
library;

const _months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

String _two(int n) => n.toString().padLeft(2, '0');

/// `3 nov 2026`
String formatDate(DateTime date) => '${date.day} ${_months[date.month - 1]} ${date.year}';

/// `3 nov 2026, 14:07`
String formatDateTime(DateTime date) => '${formatDate(date)}, ${_two(date.hour)}:${_two(date.minute)}';

/// `512 B`, `34 KB`, `1,2 MB`
String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} MB';
}
