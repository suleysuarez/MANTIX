/// Fechas y reglas del calendario de mantenimiento, en hora local y con la semana de lunes a
/// domingo. Funciones puras portadas de la web (`calendar-utils.ts` y `hub`) para que ambas
/// muestren lo mismo.
library;

import '../../models/maintenance/maintenance_models.dart';

const _months = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];

/// Cabecera de la semana, de lunes a domingo.
const weekdayLabels = ['LUN', 'MAR', 'MIÉ', 'JUE', 'VIE', 'SÁB', 'DOM'];

DateTime startOfDay(DateTime date) => DateTime(date.year, date.month, date.day);

DateTime addDays(DateTime date, int days) => DateTime(date.year, date.month, date.day + days);

bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Clave estable `YYYY-MM-DD` del día local.
String dayKey(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// Lunes de la semana de [date].
DateTime startOfWeek(DateTime date) => addDays(startOfDay(date), -(date.weekday - 1));

/// Primer día del mes de [date].
DateTime monthStart(DateTime date) => DateTime(date.year, date.month);

/// Mueve el mes [direction] meses (−1 o 1) y devuelve su primer día.
DateTime shiftMonth(DateTime anchor, int direction) => DateTime(anchor.year, anchor.month + direction);

/// Un día de la cuadrícula del mes.
class CalendarDay {
  const CalendarDay({required this.date, required this.inMonth, required this.today});

  final DateTime date;
  final bool inMonth;
  final bool today;

  String get key => dayKey(date);
}

/// La cuadrícula del mes en semanas completas (de 4 a 6 filas) que empiezan en lunes.
List<CalendarDay> monthGrid(DateTime anchor, {DateTime? today}) {
  final now = today ?? DateTime.now();
  final first = DateTime(anchor.year, anchor.month);
  final last = DateTime(anchor.year, anchor.month + 1, 0);
  final end = addDays(startOfWeek(last), 7);
  return [
    for (var day = startOfWeek(first); day.isBefore(end); day = addDays(day, 1)) CalendarDay(date: day, inMonth: day.month == anchor.month, today: sameDay(day, now)),
  ];
}

/// El rango `[start, end)` que cubre la cuadrícula del mes, para pedírselo al servidor (que admite
/// como máximo 62 días: la cuadrícula tiene como mucho 42).
({DateTime start, DateTime end}) visibleRange(DateTime anchor) {
  final days = monthGrid(anchor);
  return (start: days.first.date, end: addDays(days.last.date, 1));
}

/// «Octubre 2026».
String monthTitle(DateTime anchor) {
  final name = _months[anchor.month - 1];
  return '${name[0].toUpperCase()}${name.substring(1)} ${anchor.year}';
}

/// Agrupa los servicios por día local.
Map<String, List<CalendarEvent>> groupByDay(Iterable<CalendarEvent> events) {
  final groups = <String, List<CalendarEvent>>{};
  for (final event in events) {
    groups.putIfAbsent(dayKey(event.at), () => []).add(event);
  }
  return groups;
}

/// Nombre del estado de un servicio del calendario.
String eventLabel(CalendarEvent event) => switch (event.kind) {
      CalendarKind.overdue => 'Vencido',
      CalendarKind.planned => 'Programado',
      CalendarKind.done => event.onTime == false ? 'Con retraso' : 'A tiempo',
    };

/// Nombre del estado de un plan.
String scheduleStateLabel(ScheduleState state) => switch (state) {
      ScheduleState.planned => 'Programado',
      ScheduleState.overdue => 'Vencido',
      ScheduleState.inactive => 'Inactivo',
    };

/// Los próximos servicios: los vencidos primero y después los programados, cada grupo del más
/// próximo al más lejano. Los servicios ya hechos no cuentan. [limit] recorta la lista.
List<CalendarEvent> upcomingEvents(Iterable<CalendarEvent> events, {int? limit}) {
  final pending = [for (final event in events) if (event.kind != CalendarKind.done) event]
    ..sort((a, b) {
      if ((a.kind == CalendarKind.overdue) != (b.kind == CalendarKind.overdue)) return a.kind == CalendarKind.overdue ? -1 : 1;
      return a.at.compareTo(b.at);
    });
  return limit == null || pending.length <= limit ? pending : pending.sublist(0, limit);
}
