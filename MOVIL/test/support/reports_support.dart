/// Respuestas de ejemplo de la API de reportes, con la forma del backend.
library;

import 'package:mantix/models/reports/report_models.dart';

Map<String, Object?> option(String value, String label) => {'value': value, 'label': label};

Map<String, Object?> filterJson(String key, String label, String kind, [List<Map<String, Object?>> options = const []]) => {'key': key, 'label': label, 'kind': kind, 'options': options};

Map<String, Object?> reportJson(String key, String title, List<Map<String, Object?>> filters, {bool compare = false}) => {
      'key': key,
      'title': title,
      'description': 'Descripción de $title.',
      'icon': 'description',
      'filters': filters,
      'supports_compare': compare,
    };

Map<String, Object?> ticketsReport() => reportJson(
      'tickets',
      'Tickets de mantenimiento',
      [
        filterJson('statuses', 'Estado', 'multiselect', [option('submitted', 'Recibido'), option('in_progress', 'En proceso'), option('resolved', 'Resuelto')]),
        filterJson('priorities', 'Prioridad', 'multiselect', [option('critical', 'Crítica'), option('high', 'Alta')]),
        filterJson('dates', 'Fechas', 'dates'),
      ],
      compare: true,
    );

Map<String, Object?> plansReport() => reportJson(
      'maintenance_plans',
      'Planes de mantenimiento',
      [
        filterJson('statuses', 'Estado', 'multiselect', [option('active', 'Activo'), option('overdue', 'Vencido')]),
        filterJson('dates', 'Fechas', 'dates'),
      ],
      compare: true,
    );

Map<String, Object?> equipmentReport() => reportJson('equipment', 'Inventario de equipos', [
      filterJson('statuses', 'Estado', 'multiselect', [option('assigned', 'Asignado'), option('in_repair', 'En reparación')]),
      filterJson('equipment_type_ids', 'Tipo de equipo', 'multiselect', [option('1', 'Laptop'), option('2', 'Impresora')]),
    ]);

Map<String, Object?> summaryReport() => reportJson('summary', 'Resumen operativo', [
      filterJson('days', 'Periodo', 'days', [option('7', 'Últimos 7 días'), option('30', 'Últimos 30 días'), option('90', 'Últimos 90 días')]),
    ]);

/// Un reporte que la app no ofrece (la app no tiene módulo de inventario).
Map<String, Object?> inventoryReport() => reportJson('inventory_items', 'Existencias del inventario', [
      filterJson('categories', 'Categoría', 'multiselect', [option('cables', 'Cables')]),
    ]);

/// El catálogo con los 6 reportes del servidor, en un orden distinto al de la app.
Map<String, Object?> catalogJson({List<Map<String, Object?>>? reports, int maxRows = 10000}) => {
      'reports': reports ?? [summaryReport(), inventoryReport(), equipmentReport(), ticketsReport(), plansReport()],
      'max_rows': maxRows,
      'max_range_days': 366,
      'formats': ['xlsx', 'pdf', 'csv'],
    };

Map<String, Object?> previewJson({String report = 'tickets', int total = 3, bool truncated = false, List<Map<String, String>>? rows, Map<String, Object?>? comparison}) => {
      'report': report,
      'title': 'Tickets de mantenimiento',
      'columns': [
        {'key': 'ticket_number', 'header': 'Ticket'},
        {'key': 'title', 'header': 'Título'},
        {'key': 'status', 'header': 'Estado'},
      ],
      'rows': rows ?? [for (var i = 1; i <= (total < 3 ? total : 3); i++) {'ticket_number': 'TCK-00$i', 'title': 'Ticket $i', 'status': 'En proceso'}],
      'total_rows': total,
      'truncated': truncated,
      'comparison': comparison,
    };

Map<String, Object?> comparisonJson({int current = 12, int previous = 10, double? change = 20}) => {
      'current_total': current,
      'previous_total': previous,
      'change_pct': change,
      'previous_from': '2026-09-01T05:00:00Z',
      'previous_to': '2026-09-30T05:00:00Z',
    };

Map<String, Object?> runJson({int id = 1, String report = 'tickets', String format = 'xlsx', int rows = 25, String? by = 'Ana Pérez', String at = '2026-11-10T15:30:00Z'}) => {
      'id': id,
      'report': report,
      'title': 'Tickets de mantenimiento',
      'export_format': format,
      'row_count': rows,
      'filters': <String, Object?>{},
      'by': by,
      'at': at,
    };

/// Los reportes de la app ya convertidos a modelos, para las pruebas que no pasan por la API.
List<ReportDefinition> appReports() => [for (final json in [ticketsReport(), plansReport(), equipmentReport(), summaryReport()]) ReportDefinition.fromJson(json)];

ReportDefinition reportOf(String key) => appReports().firstWhere((report) => report.key == key);
