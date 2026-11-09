/// Formatos del inventario exportado (`GET /reports/equipment?format=`).
enum ExportFormat {
  xlsx('xlsx', 'Excel', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
  csv('csv', 'CSV', 'text/csv'),
  pdf('pdf', 'PDF', 'application/pdf');

  const ExportFormat(this.extension, this.label, this.mimeType);

  /// Valor del parámetro `format` y extensión del archivo.
  final String extension;
  final String label;
  final String mimeType;
}
