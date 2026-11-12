/// Filtros, validaciones y textos de la pantalla de reportes. Funciones puras portadas de la web
/// (`report-filters.ts` y `export-model.ts`) para que ambas pidan y expliquen lo mismo.
library;

import 'package:equatable/equatable.dart';

import '../../models/reports/report_models.dart';
import 'formatters.dart';
import 'maintenance_calendar.dart' show dayKey, startOfDay;
import 'users_format.dart' show lastAccessText;

/// Los reportes que ofrece la app, en este orden: los que sirven en el día a día de quien
/// supervisa. Los demás del catálogo (existencias y movimientos de inventario) no se muestran
/// porque la app no tiene módulo de inventario.
const relevantReports = ['tickets', 'maintenance_plans', 'equipment', 'summary'];

/// El rango de fechas de un reporte no puede pasar de estos días (igual que el servidor).
const maxReportRangeDays = 366;

/// Desde cuántas filas el archivo tarda en generarse (igual que la web).
const warnRows = 2000;

/// Del catálogo, solo los reportes de [relevantReports], en su orden.
List<ReportDefinition> relevantOf(Iterable<ReportDefinition> reports) {
  final byKey = {for (final report in reports) report.key: report};
  return [for (final key in relevantReports) if (byKey[key] != null) byKey[key]!];
}

/// Lo que la persona eligió en los filtros. Un conjunto vacío no filtra. Solo se envía lo que el
/// reporte admite (ver [toApiFilters]).
class ReportFilterValues extends Equatable {
  const ReportFilterValues({this.statuses = const {}, this.priorities = const {}, this.categories = const {}, this.kinds = const {}, this.equipmentTypeIds = const {}, this.dateFrom, this.dateTo, this.days = defaultDays, this.compare = false});

  static const defaultDays = '30';

  final Set<String> statuses;
  final Set<String> priorities;
  final Set<String> categories;
  final Set<String> kinds;
  final Set<String> equipmentTypeIds;

  /// Día (a medianoche, hora local); `null` = sin límite.
  final DateTime? dateFrom;
  final DateTime? dateTo;

  /// Ventana del resumen operativo, en días.
  final String days;

  /// Comparar con el periodo anterior (necesita las dos fechas).
  final bool compare;

  Set<String> selected(String key) => switch (key) {
        'statuses' => statuses,
        'priorities' => priorities,
        'categories' => categories,
        'kinds' => kinds,
        'equipment_type_ids' => equipmentTypeIds,
        _ => const {},
      };

  ReportFilterValues withSelected(String key, Set<String> values) => copyWith(
        statuses: key == 'statuses' ? values : null,
        priorities: key == 'priorities' ? values : null,
        categories: key == 'categories' ? values : null,
        kinds: key == 'kinds' ? values : null,
        equipmentTypeIds: key == 'equipment_type_ids' ? values : null,
      );

  ReportFilterValues copyWith({Set<String>? statuses, Set<String>? priorities, Set<String>? categories, Set<String>? kinds, Set<String>? equipmentTypeIds, DateTime? dateFrom, DateTime? dateTo, bool clearDates = false, String? days, bool? compare}) => ReportFilterValues(
        statuses: statuses ?? this.statuses,
        priorities: priorities ?? this.priorities,
        categories: categories ?? this.categories,
        kinds: kinds ?? this.kinds,
        equipmentTypeIds: equipmentTypeIds ?? this.equipmentTypeIds,
        dateFrom: clearDates ? null : (dateFrom ?? this.dateFrom),
        dateTo: clearDates ? null : (dateTo ?? this.dateTo),
        days: days ?? this.days,
        compare: compare ?? this.compare,
      );

  /// Cuántos filtros de [definition] hay puestos (para el contador del botón). El comparativo y la
  /// ventana por defecto del resumen no cuentan.
  int activeCount(ReportDefinition definition) {
    var count = 0;
    for (final filter in definition.filters) {
      switch (filter.kind) {
        case ReportFilterKind.multiselect:
          if (selected(filter.key).isNotEmpty) count++;
        case ReportFilterKind.dates:
          if (dateFrom != null || dateTo != null) count++;
        case ReportFilterKind.days:
          if (days != defaultDays) count++;
      }
    }
    return count;
  }

  @override
  List<Object?> get props => [statuses, priorities, categories, kinds, equipmentTypeIds, dateFrom, dateTo, days, compare];
}

/// Error del rango de fechas, o `null` si es válido: la final no puede ser anterior a la inicial
/// y el rango cubre como máximo 366 días. A diferencia de otros filtros, puede ser futuro (los
/// planes de mantenimiento tienen fechas por venir).
String? reportRangeError(DateTime? from, DateTime? to) {
  if (from == null || to == null) return null;
  final start = DateTime.utc(from.year, from.month, from.day);
  final end = DateTime.utc(to.year, to.month, to.day);
  if (end.isBefore(start)) return 'La fecha final no puede ser anterior a la inicial.';
  if (end.difference(start).inDays + 1 > maxReportRangeDays) return 'El rango no puede superar $maxReportRangeDays días.';
  return null;
}

/// Inicio (00:00) o fin (23:59:59.999) del día local, como ISO UTC.
String dayBoundaryIso(DateTime day, {required bool end}) {
  final local = end ? DateTime(day.year, day.month, day.day, 23, 59, 59, 999) : startOfDay(day);
  return local.toUtc().toIso8601String();
}

/// Los filtros tal como los espera la API. Solo viaja lo que el reporte admite y lo que se eligió:
/// cambiar de reporte no arrastra filtros de otro (el servidor rechazaría uno que no acepta).
Map<String, Object?> toApiFilters(ReportDefinition definition, ReportFilterValues values) {
  final filters = <String, Object?>{};
  for (final filter in definition.filters) {
    switch (filter.kind) {
      case ReportFilterKind.multiselect:
        final chosen = values.selected(filter.key);
        if (chosen.isEmpty) break;
        // Mantiene el orden de las opciones del catálogo, no el del toque.
        final ordered = [for (final option in filter.options) if (chosen.contains(option.value)) option.value];
        final list = ordered.isEmpty ? chosen.toList() : ordered;
        filters[filter.key] = filter.key == 'equipment_type_ids' ? [for (final id in list) int.tryParse(id) ?? id] : list;
      case ReportFilterKind.dates:
        if (values.dateFrom != null) filters['date_from'] = dayBoundaryIso(values.dateFrom!, end: false);
        if (values.dateTo != null) filters['date_to'] = dayBoundaryIso(values.dateTo!, end: true);
      case ReportFilterKind.days:
        filters['days'] = int.tryParse(values.days) ?? 30;
    }
  }
  return filters;
}

/// El comparativo necesita las dos fechas del rango y un reporte que lo admita.
bool canCompare(ReportDefinition definition, ReportFilterValues values) => definition.supportsCompare && values.dateFrom != null && values.dateTo != null;

/// Resumen legible de los filtros activos: «Estados: Abierto, Cerrado · Fechas: 1 oct 2026 a …».
String describeFilters(ReportDefinition definition, ReportFilterValues values) {
  final parts = <String>[];
  for (final filter in definition.filters) {
    switch (filter.kind) {
      case ReportFilterKind.multiselect:
        final chosen = values.selected(filter.key);
        if (chosen.isNotEmpty) parts.add('${filter.label}: ${[for (final option in filter.options) if (chosen.contains(option.value)) option.label].join(', ')}');
      case ReportFilterKind.dates:
        if (values.dateFrom != null || values.dateTo != null) {
          parts.add('${filter.label}: ${values.dateFrom == null ? '…' : formatDate(values.dateFrom!)} a ${values.dateTo == null ? '…' : formatDate(values.dateTo!)}');
        }
      case ReportFilterKind.days:
        parts.add(filter.options.where((o) => o.value == values.days).map((o) => o.label).firstOrNull ?? 'Últimos ${values.days} días');
    }
  }
  return parts.isEmpty ? 'Sin filtros' : parts.join(' · ');
}

enum CountTone { ok, warn, error }

String _grouped(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// El contador de lo que se exportará: con cuántos registros, y si hay demasiados o ninguno.
({String text, CountTone tone}) countMessage(int total, int maxRows, {int warn = warnRows}) {
  if (total == 0) return (text: 'Ningún registro coincide con estos filtros. Amplía el rango de fechas o quita algún filtro.', tone: CountTone.error);
  if (total > maxRows) return (text: 'Son ${_grouped(total)} registros y el máximo es ${_grouped(maxRows)}. Acota los filtros para exportar.', tone: CountTone.error);
  final noun = total == 1 ? 'registro' : 'registros';
  final verb = total == 1 ? 'Se exportará' : 'Se exportarán';
  if (total > warn) return (text: '$verb ${_grouped(total)} $noun. Es un archivo grande: puede tardar en generarse.', tone: CountTone.warn);
  return (text: '$verb ${_grouped(total)} $noun.', tone: CountTone.ok);
}

/// El nombre del archivo, como el del servidor: `mantix_tickets_2026-11-11.xlsx`.
String reportFileName(String report, ReportFormat format, DateTime now) => 'mantix_${report}_${dayKey(now)}.${format.extension}';

/// Cuándo fue la última exportación: «Ahora mismo», «Hace 5 min», «Hace 3 h», «Hace 2 días» o la
/// fecha si pasó un mes. Sin ninguna, «Sin exportar».
String lastExportText(DateTime? at, DateTime now) => at == null ? 'Sin exportar' : lastAccessText(at, now);
