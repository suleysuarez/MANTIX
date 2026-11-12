import 'package:equatable/equatable.dart';

DateTime? _date(Object? value) => value is String ? DateTime.tryParse(value)?.toLocal() : null;

int _int(Object? value) => value is num ? value.toInt() : 0;

/// Formato en que se descarga un reporte. La app solo ofrece Excel y PDF; el servidor admite
/// además CSV, que aquí no se pide.
enum ReportFormat {
  xlsx('xlsx', 'Excel', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
  pdf('pdf', 'PDF', 'application/pdf');

  const ReportFormat(this.extension, this.label, this.mimeType);

  /// Valor de `format` en la API y extensión del archivo.
  final String extension;
  final String label;
  final String mimeType;
}

class ReportFilterOption extends Equatable {
  const ReportFilterOption({required this.value, required this.label});

  factory ReportFilterOption.fromJson(Map<String, Object?> json) => ReportFilterOption(value: '${json['value']}', label: '${json['label']}');

  final String value;
  final String label;

  @override
  List<Object?> get props => [value, label];
}

enum ReportFilterKind { multiselect, dates, days }

/// Un filtro que acepta un reporte, tal como lo da el catálogo. [key] es `statuses`, `priorities`,
/// `categories`, `kinds`, `equipment_type_ids`, `dates` o `days`.
class ReportFilterDefinition extends Equatable {
  const ReportFilterDefinition({required this.key, required this.label, required this.kind, this.options = const []});

  factory ReportFilterDefinition.fromJson(Map<String, Object?> json) {
    final options = json['options'];
    return ReportFilterDefinition(
      key: json['key']! as String,
      label: json['label']! as String,
      kind: switch (json['kind']) {
        'dates' => ReportFilterKind.dates,
        'days' => ReportFilterKind.days,
        _ => ReportFilterKind.multiselect,
      },
      options: [if (options is List) for (final item in options.whereType<Map>()) ReportFilterOption.fromJson(item.cast<String, Object?>())],
    );
  }

  final String key;
  final String label;
  final ReportFilterKind kind;
  final List<ReportFilterOption> options;

  String labelOf(String value) {
    for (final option in options) {
      if (option.value == value) return option.label;
    }
    return value;
  }

  @override
  List<Object?> get props => [key, label, kind, options];
}

/// Un reporte del catálogo: qué es y qué filtros acepta. El servidor rechaza un filtro que el
/// reporte no admite, así que solo se envían los de [filters].
class ReportDefinition extends Equatable {
  const ReportDefinition({required this.key, required this.title, required this.description, required this.icon, this.filters = const [], this.supportsCompare = false});

  factory ReportDefinition.fromJson(Map<String, Object?> json) {
    final filters = json['filters'];
    return ReportDefinition(
      key: json['key']! as String,
      title: json['title']! as String,
      description: (json['description'] as String?) ?? '',
      icon: (json['icon'] as String?) ?? '',
      filters: [if (filters is List) for (final item in filters.whereType<Map>()) ReportFilterDefinition.fromJson(item.cast<String, Object?>())],
      supportsCompare: json['supports_compare'] as bool? ?? false,
    );
  }

  final String key;
  final String title;
  final String description;

  /// Nombre de icono de Material Symbols (el de la web); la app usa el suyo según [key].
  final String icon;
  final List<ReportFilterDefinition> filters;
  final bool supportsCompare;

  ReportFilterDefinition? filter(String key) {
    for (final candidate in filters) {
      if (candidate.key == key) return candidate;
    }
    return null;
  }

  @override
  List<Object?> get props => [key, title, description, icon, filters, supportsCompare];
}

class ReportCatalog extends Equatable {
  const ReportCatalog({required this.reports, required this.maxRows, required this.maxRangeDays});

  factory ReportCatalog.fromJson(Map<String, Object?> json) {
    final reports = json['reports'];
    return ReportCatalog(
      reports: [if (reports is List) for (final item in reports.whereType<Map>()) ReportDefinition.fromJson(item.cast<String, Object?>())],
      maxRows: json['max_rows'] is num ? _int(json['max_rows']) : 10000,
      maxRangeDays: json['max_range_days'] is num ? _int(json['max_range_days']) : 366,
    );
  }

  final List<ReportDefinition> reports;

  /// Más filas que esto no se exporta: se piden filtros más estrechos.
  final int maxRows;
  final int maxRangeDays;

  @override
  List<Object?> get props => [reports, maxRows, maxRangeDays];
}

class PreviewColumn extends Equatable {
  const PreviewColumn({required this.key, required this.header});

  factory PreviewColumn.fromJson(Map<String, Object?> json) => PreviewColumn(key: json['key']! as String, header: json['header']! as String);

  final String key;
  final String header;

  @override
  List<Object?> get props => [key, header];
}

/// Las filas del mismo reporte en el periodo anterior de igual duración.
class ReportComparison extends Equatable {
  const ReportComparison({required this.currentTotal, required this.previousTotal, this.changePct, this.previousFrom, this.previousTo});

  factory ReportComparison.fromJson(Map<String, Object?> json) => ReportComparison(
        currentTotal: _int(json['current_total']),
        previousTotal: _int(json['previous_total']),
        changePct: json['change_pct'] is num ? (json['change_pct']! as num).toDouble() : null,
        previousFrom: _date(json['previous_from']),
        previousTo: _date(json['previous_to']),
      );

  final int currentTotal;
  final int previousTotal;

  /// `null` cuando el periodo anterior no tiene filas con las que comparar.
  final double? changePct;
  final DateTime? previousFrom;
  final DateTime? previousTo;

  @override
  List<Object?> get props => [currentTotal, previousTotal, changePct, previousFrom, previousTo];
}

/// Las primeras filas de un reporte y cuántas hay en total (`POST /reports/preview`). Cada fila
/// ya viene formateada, con un texto por columna.
class ReportPreview extends Equatable {
  const ReportPreview({required this.report, required this.title, required this.columns, required this.rows, required this.totalRows, this.truncated = false, this.comparison});

  factory ReportPreview.fromJson(Map<String, Object?> json) {
    final columns = json['columns'];
    final rows = json['rows'];
    return ReportPreview(
      report: json['report']! as String,
      title: (json['title'] as String?) ?? '',
      columns: [if (columns is List) for (final item in columns.whereType<Map>()) PreviewColumn.fromJson(item.cast<String, Object?>())],
      rows: [
        if (rows is List)
          for (final row in rows.whereType<Map>()) {for (final entry in row.entries) '${entry.key}': '${entry.value ?? ''}'},
      ],
      totalRows: _int(json['total_rows']),
      truncated: json['truncated'] as bool? ?? false,
      comparison: json['comparison'] is Map ? ReportComparison.fromJson((json['comparison']! as Map).cast<String, Object?>()) : null,
    );
  }

  final String report;
  final String title;
  final List<PreviewColumn> columns;
  final List<Map<String, String>> rows;
  final int totalRows;

  /// Hay más filas que el límite de exportación.
  final bool truncated;
  final ReportComparison? comparison;

  @override
  List<Object?> get props => [report, title, columns, rows, totalRows, truncated, comparison];
}

/// Una exportación ya hecha (`GET /reports/history`).
class ReportRun extends Equatable {
  const ReportRun({required this.id, required this.report, required this.title, required this.format, required this.rowCount, required this.at, this.by});

  factory ReportRun.fromJson(Map<String, Object?> json) => ReportRun(
        id: json['id']! as int,
        report: json['report']! as String,
        title: (json['title'] as String?) ?? '',
        format: (json['export_format'] as String?) ?? '',
        rowCount: _int(json['row_count']),
        by: json['by'] as String?,
        at: _date(json['at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      );

  final int id;
  final String report;
  final String title;

  /// `xlsx`, `pdf` o `csv` (la web también exporta CSV).
  final String format;
  final int rowCount;

  /// Quién lo generó; `null` si fue el sistema.
  final String? by;
  final DateTime at;

  String get formatLabel => switch (format) {
        'xlsx' => 'Excel',
        'pdf' => 'PDF',
        'csv' => 'CSV',
        _ => format.toUpperCase(),
      };

  @override
  List<Object?> get props => [id, report, title, format, rowCount, by, at];
}
