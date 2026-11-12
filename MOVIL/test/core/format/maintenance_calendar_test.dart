import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/format/maintenance_calendar.dart';
import 'package:mantix/models/maintenance/maintenance_models.dart';

import '../../support/maintenance_support.dart';

void main() {
  group('cuadrícula del mes (semana de lunes a domingo)', () {
    test('octubre de 2026 empieza el lunes 28 de septiembre y acaba el domingo 1 de noviembre', () {
      final days = monthGrid(DateTime(2026, 10), today: DateTime(2026, 10, 25));

      expect(days, hasLength(35));
      expect(days.first.date, DateTime(2026, 9, 28));
      expect(days.last.date, DateTime(2026, 11, 1));
      expect(days.where((day) => day.inMonth), hasLength(31));
      expect(days.first.inMonth, isFalse);
      expect(days.where((day) => day.today).single.key, '2026-10-25');
    });

    test('un mes puede ocupar 4 o 6 filas', () {
      expect(monthGrid(DateTime(2027, 2)), hasLength(28), reason: 'febrero de 2027 empieza en lunes y acaba en domingo');
      expect(monthGrid(DateTime(2026, 11)), hasLength(42), reason: 'noviembre de 2026 empieza en domingo y acaba en lunes');
    });

    test('siempre cabe en los 62 días que admite el servidor', () {
      for (var month = 1; month <= 24; month++) {
        final range = visibleRange(DateTime(2026, month));
        expect(range.end.difference(range.start).inDays, lessThanOrEqualTo(42));
      }
    });

    test('el rango pedido es [primer día, día siguiente al último)', () {
      final range = visibleRange(DateTime(2026, 10));
      expect(range.start, DateTime(2026, 9, 28));
      expect(range.end, DateTime(2026, 11, 2));
    });

    test('hoy no se marca si no está en la cuadrícula', () {
      expect(monthGrid(DateTime(2026, 10), today: DateTime(2027, 1, 1)).where((day) => day.today), isEmpty);
    });
  });

  group('meses y días', () {
    test('el título lleva el mes con mayúscula y el año', () {
      expect(monthTitle(DateTime(2026, 10)), 'Octubre 2026');
      expect(monthTitle(DateTime(2027, 1, 15)), 'Enero 2027');
    });

    test('moverse de mes cruza los años', () {
      expect(shiftMonth(DateTime(2026, 12), 1), DateTime(2027, 1));
      expect(shiftMonth(DateTime(2026, 1), -1), DateTime(2025, 12));
      expect(monthStart(DateTime(2026, 10, 25, 9)), DateTime(2026, 10));
    });

    test('la clave del día es estable', () {
      expect(dayKey(DateTime(2026, 3, 5, 23, 59)), '2026-03-05');
      expect(startOfWeek(DateTime(2026, 10, 25)), DateTime(2026, 10, 19), reason: 'el domingo 25 pertenece a la semana del lunes 19');
      expect(sameDay(DateTime(2026, 10, 25, 1), DateTime(2026, 10, 25, 23)), isTrue);
    });

    test('la cabecera va de lunes a domingo', () {
      expect(weekdayLabels, ['LUN', 'MAR', 'MIÉ', 'JUE', 'VIE', 'SÁB', 'DOM']);
    });
  });

  group('servicios', () {
    final first = calendarEvent(id: 1, at: DateTime(2026, 10, 25, 9));
    final second = calendarEvent(id: 2, at: DateTime(2026, 10, 25, 15), kind: CalendarKind.overdue);
    final third = calendarEvent(id: 3, at: DateTime(2026, 10, 28, 9));
    final done = calendarEvent(id: 4, at: DateTime(2026, 10, 20, 9), kind: CalendarKind.done, onTime: false);

    test('se agrupan por día local', () {
      final groups = groupByDay([first, second, third]);
      expect(groups.keys, ['2026-10-25', '2026-10-28']);
      expect(groups['2026-10-25'], [first, second]);
    });

    test('los próximos: primero los vencidos y luego los programados, y no cuentan los hechos', () {
      expect(upcomingEvents([third, first, done, second]).map((e) => e.scheduleId), [2, 1, 3]);
    });

    test('se puede recortar la lista', () {
      expect(upcomingEvents([third, first, second], limit: 2).map((e) => e.scheduleId), [2, 1]);
      expect(upcomingEvents([first], limit: 5), hasLength(1));
    });

    test('nombres en español', () {
      expect(eventLabel(first), 'Programado');
      expect(eventLabel(second), 'Vencido');
      expect(eventLabel(done), 'Con retraso');
      expect(eventLabel(calendarEvent(at: DateTime(2026, 10, 1), kind: CalendarKind.done, onTime: true)), 'A tiempo');
      expect(ScheduleState.values.map(scheduleStateLabel), ['Programado', 'Vencido', 'Inactivo']);
    });
  });
}
