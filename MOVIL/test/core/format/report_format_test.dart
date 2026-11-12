import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/format/report_format.dart';
import 'package:mantix/models/reports/report_models.dart';

import '../../support/reports_support.dart';

void main() {
  group('reportes que ofrece la app', () {
    test('de todo el catálogo se queda con los 4 relevantes y en su orden', () {
      final all = [for (final json in (catalogJson()['reports']! as List).cast<Map<String, Object?>>()) ReportDefinition.fromJson(json)];

      expect(all.map((r) => r.key), ['summary', 'inventory_items', 'equipment', 'tickets', 'maintenance_plans']);
      expect(relevantOf(all).map((r) => r.key), ['tickets', 'maintenance_plans', 'equipment', 'summary']);
    });

    test('si el servidor no ofrece uno, simplemente no sale', () {
      expect(relevantOf(appReports().where((r) => r.key != 'equipment')).map((r) => r.key), ['tickets', 'maintenance_plans', 'summary']);
      expect(relevantOf(const []), isEmpty);
    });
  });

  group('filtros elegidos', () {
    test('selected y withSelected solo tocan el grupo pedido', () {
      const values = ReportFilterValues();
      final next = values.withSelected('statuses', {'in_progress'}).withSelected('equipment_type_ids', {'2'});

      expect(next.selected('statuses'), {'in_progress'});
      expect(next.selected('equipment_type_ids'), {'2'});
      expect(next.selected('priorities'), isEmpty);
      expect(next.selected('desconocido'), isEmpty);
    });

    test('quitar las fechas borra las dos', () {
      final values = ReportFilterValues(dateFrom: DateTime(2026, 10, 1), dateTo: DateTime(2026, 10, 31));
      expect(values.copyWith(clearDates: true).dateFrom, isNull);
      expect(values.copyWith(clearDates: true).dateTo, isNull);
      expect(values.copyWith(compare: true).dateFrom, DateTime(2026, 10, 1));
    });

    test('activeCount cuenta solo lo que el reporte admite', () {
      final tickets = reportOf('tickets');
      expect(const ReportFilterValues().activeCount(tickets), 0);
      expect(const ReportFilterValues(statuses: {'resolved'}, priorities: {'high'}).activeCount(tickets), 2);
      expect(ReportFilterValues(dateFrom: DateTime(2026, 10, 1)).activeCount(tickets), 1);
      // «priorities» no es un filtro de equipos: no cuenta.
      expect(const ReportFilterValues(priorities: {'high'}).activeCount(reportOf('equipment')), 0);
    });

    test('la ventana del resumen cuenta solo si no es la de 30 días, y el comparativo nunca', () {
      final summary = reportOf('summary');
      expect(const ReportFilterValues().activeCount(summary), 0);
      expect(const ReportFilterValues(days: '7').activeCount(summary), 1);
      expect(const ReportFilterValues(compare: true).activeCount(reportOf('tickets')), 0);
    });
  });

  group('rango de fechas', () {
    test('sin una de las dos fechas no hay error', () {
      expect(reportRangeError(null, null), isNull);
      expect(reportRangeError(DateTime(2026, 10, 1), null), isNull);
      expect(reportRangeError(null, DateTime(2026, 10, 1)), isNull);
    });

    test('la final no puede ser anterior a la inicial', () {
      expect(reportRangeError(DateTime(2026, 10, 5), DateTime(2026, 10, 4)), 'La fecha final no puede ser anterior a la inicial.');
      expect(reportRangeError(DateTime(2026, 10, 5), DateTime(2026, 10, 5)), isNull);
    });

    test('como máximo 366 días contando los dos extremos', () {
      expect(reportRangeError(DateTime(2026, 1, 1), DateTime(2026, 12, 31)), isNull, reason: '365 días');
      expect(reportRangeError(DateTime(2026, 1, 1), DateTime(2027, 1, 1)), isNull, reason: '366 días');
      expect(reportRangeError(DateTime(2026, 1, 1), DateTime(2027, 1, 2)), 'El rango no puede superar 366 días.');
    });

    test('puede ser futuro: los planes tienen fechas por venir', () {
      expect(reportRangeError(DateTime(2030, 1, 1), DateTime(2030, 1, 31)), isNull);
    });
  });

  group('filtros para la API', () {
    test('las fechas van del inicio al final del día local, en UTC', () {
      expect(dayBoundaryIso(DateTime(2026, 10, 5, 15, 30), end: false), DateTime(2026, 10, 5).toUtc().toIso8601String());
      expect(dayBoundaryIso(DateTime(2026, 10, 5, 3), end: true), DateTime(2026, 10, 5, 23, 59, 59, 999).toUtc().toIso8601String());
    });

    test('solo viaja lo elegido y en el orden del catálogo', () {
      final filters = toApiFilters(reportOf('tickets'), ReportFilterValues(statuses: const {'resolved', 'submitted'}, priorities: const {'high'}, dateFrom: DateTime(2026, 10, 1), dateTo: DateTime(2026, 10, 31)));

      expect(filters['statuses'], ['submitted', 'resolved']);
      expect(filters['priorities'], ['high']);
      expect(filters['date_from'], DateTime(2026, 10, 1).toUtc().toIso8601String());
      expect(filters['date_to'], DateTime(2026, 10, 31, 23, 59, 59, 999).toUtc().toIso8601String());
      expect(filters.keys, unorderedEquals(['statuses', 'priorities', 'date_from', 'date_to']));
    });

    test('sin elegir nada no viaja nada (salvo la ventana del resumen)', () {
      expect(toApiFilters(reportOf('tickets'), const ReportFilterValues()), isEmpty);
      expect(toApiFilters(reportOf('equipment'), const ReportFilterValues()), isEmpty);
      expect(toApiFilters(reportOf('summary'), const ReportFilterValues()), {'days': 30});
    });

    test('un filtro que el reporte no admite no viaja, aunque esté elegido', () {
      const values = ReportFilterValues(statuses: {'in_repair'}, priorities: {'high'}, kinds: {'in'}, categories: {'cables'}, days: '7');

      expect(toApiFilters(reportOf('equipment'), values), {'statuses': ['in_repair']});
      // Los planes solo admiten estados y fechas: prioridades, tipos, categorías y días no viajan.
      expect(toApiFilters(reportOf('maintenance_plans'), values).keys, ['statuses']);
    });

    test('los tipos de equipo viajan como números', () {
      expect(toApiFilters(reportOf('equipment'), const ReportFilterValues(equipmentTypeIds: {'2', '1'})), {'equipment_type_ids': [1, 2]});
    });

    test('la ventana del resumen viaja como número', () {
      expect(toApiFilters(reportOf('summary'), const ReportFilterValues(days: '90')), {'days': 90});
      expect(toApiFilters(reportOf('summary'), const ReportFilterValues(days: 'x')), {'days': 30});
    });

    test('fechas sueltas: solo viaja la que hay', () {
      expect(toApiFilters(reportOf('tickets'), ReportFilterValues(dateFrom: DateTime(2026, 10, 1))).keys, ['date_from']);
      expect(toApiFilters(reportOf('tickets'), ReportFilterValues(dateTo: DateTime(2026, 10, 1))).keys, ['date_to']);
    });
  });

  group('comparativo', () {
    test('necesita un reporte que lo admita y las dos fechas', () {
      final both = ReportFilterValues(dateFrom: DateTime(2026, 10, 1), dateTo: DateTime(2026, 10, 31));
      expect(canCompare(reportOf('tickets'), both), isTrue);
      expect(canCompare(reportOf('maintenance_plans'), both), isTrue);
      expect(canCompare(reportOf('equipment'), both), isFalse);
      expect(canCompare(reportOf('tickets'), ReportFilterValues(dateFrom: DateTime(2026, 10, 1))), isFalse);
      expect(canCompare(reportOf('tickets'), const ReportFilterValues()), isFalse);
    });
  });

  group('resumen de los filtros', () {
    test('sin filtros', () => expect(describeFilters(reportOf('tickets'), const ReportFilterValues()), 'Sin filtros'));

    test('lista lo elegido con los nombres del catálogo', () {
      final text = describeFilters(reportOf('tickets'), ReportFilterValues(statuses: const {'resolved', 'submitted'}, priorities: const {'high'}, dateFrom: DateTime(2026, 10, 1)));
      expect(text, 'Estado: Recibido, Resuelto · Prioridad: Alta · Fechas: 1 oct 2026 a …');
    });

    test('las dos fechas', () {
      expect(describeFilters(reportOf('maintenance_plans'), ReportFilterValues(dateFrom: DateTime(2026, 10, 1), dateTo: DateTime(2026, 10, 31))), 'Fechas: 1 oct 2026 a 31 oct 2026');
    });

    test('el resumen siempre dice su ventana', () {
      expect(describeFilters(reportOf('summary'), const ReportFilterValues()), 'Últimos 30 días');
      expect(describeFilters(reportOf('summary'), const ReportFilterValues(days: '7')), 'Últimos 7 días');
      expect(describeFilters(reportOf('summary'), const ReportFilterValues(days: '45')), 'Últimos 45 días');
    });
  });

  group('contador de lo que se exportará', () {
    test('ningún registro es un error', () {
      final result = countMessage(0, 10000);
      expect(result.tone, CountTone.error);
      expect(result.text, startsWith('Ningún registro coincide'));
    });

    test('más del máximo pide acotar y escribe los miles con punto', () {
      final result = countMessage(12345, 10000);
      expect(result.tone, CountTone.error);
      expect(result.text, 'Son 12.345 registros y el máximo es 10.000. Acota los filtros para exportar.');
    });

    test('un archivo grande avisa de que tarda', () {
      final result = countMessage(2500, 10000);
      expect(result.tone, CountTone.warn);
      expect(result.text, 'Se exportarán 2.500 registros. Es un archivo grande: puede tardar en generarse.');
    });

    test('lo normal, en singular y plural', () {
      expect(countMessage(1, 10000), (text: 'Se exportará 1 registro.', tone: CountTone.ok));
      expect(countMessage(25, 10000), (text: 'Se exportarán 25 registros.', tone: CountTone.ok));
    });

    test('justo en los límites', () {
      expect(countMessage(10000, 10000).tone, CountTone.warn, reason: 'el máximo todavía se exporta');
      expect(countMessage(2000, 10000).tone, CountTone.ok, reason: 'el aviso empieza después de 2.000');
      expect(countMessage(2001, 10000).tone, CountTone.warn);
    });
  });

  test('el nombre del archivo es el del servidor', () {
    expect(reportFileName('tickets', ReportFormat.xlsx, DateTime(2026, 11, 11, 23, 59)), 'mantix_tickets_2026-11-11.xlsx');
    expect(reportFileName('maintenance_plans', ReportFormat.pdf, DateTime(2026, 3, 5)), 'mantix_maintenance_plans_2026-03-05.pdf');
  });

  test('solo hay dos formatos: Excel y PDF', () {
    expect(ReportFormat.values.map((f) => f.label), ['Excel', 'PDF']);
    expect(ReportFormat.values.map((f) => f.extension), ['xlsx', 'pdf']);
  });

  group('lastExportText', () {
    final now = DateTime(2026, 11, 10, 17, 30);

    test('sin exportaciones dice «Sin exportar», nunca «Nunca»', () {
      expect(lastExportText(null, now), 'Sin exportar');
    });

    test('con una exportación dice cuánto pasó', () {
      expect(lastExportText(now.subtract(const Duration(seconds: 10)), now), 'Ahora mismo');
      expect(lastExportText(now.subtract(const Duration(minutes: 5)), now), 'Hace 5 min');
      expect(lastExportText(now.subtract(const Duration(hours: 2)), now), 'Hace 2 h');
      expect(lastExportText(now.subtract(const Duration(days: 3)), now), 'Hace 3 días');
    });
  });
}
