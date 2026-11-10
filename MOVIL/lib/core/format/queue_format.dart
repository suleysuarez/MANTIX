/// Formato y reglas de la bandeja de triaje. Funciones puras, portadas de la web
/// (`dashboard-format.ts` y `pending-ui.ts`) para que ambas muestren lo mismo.
library;

import '../../models/catalogs/catalog_models.dart';

/// Color semántico de una variación: depende de si subir es bueno o malo.
enum ChangeTone { good, bad, neutral }

/// Cuánto lleva esperando una solicitud.
enum WaitTone { fresh, aging, stale }

/// Más de 1 día pide atención; más de 3 días es una espera que ya molesta.
const agingHours = 24;
const staleHours = 72;

const minReasonLength = 5;
const maxReasonLength = 500;

/// Rango máximo de un filtro por fechas, en días.
const maxRangeDays = 366;

String _decimal(double value) => value.toStringAsFixed(1).replaceAll('.', ',').replaceFirst(RegExp(r',0$'), '');

/// «45 min», «12,5 h» o «3,2 d»: la unidad que mejor se lee según la magnitud.
String formatHours(double? hours) {
  if (hours == null) return '—';
  if (hours < 1) {
    final minutes = (hours * 60).round();
    return '${minutes < 1 ? 1 : minutes} min';
  }
  return hours < 48 ? '${_decimal(hours)} h' : '${_decimal(hours / 24)} d';
}

String formatPct(double? value) => value == null ? '—' : '${_decimal(value)}%';

/// Variación con flecha: «▲ 12,5%». Vacío cuando no hay base de comparación.
String formatChange(double? changePct) {
  if (changePct == null) return '';
  if (changePct == 0) return '= 0%';
  return '${changePct > 0 ? '▲' : '▼'} ${_decimal(changePct.abs())}%';
}

/// [betterWhenHigher] indica si subir es bueno (aprobación) o malo (tiempo de respuesta).
ChangeTone changeTone(double? changePct, {required bool betterWhenHigher}) {
  if (changePct == null || changePct == 0) return ChangeTone.neutral;
  final improved = betterWhenHigher ? changePct > 0 : changePct < 0;
  return improved ? ChangeTone.good : ChangeTone.bad;
}

/// Horas que una solicitud lleva en cola; nunca negativas (relojes desfasados).
double waitHours(DateTime createdAt, DateTime now) {
  final hours = now.difference(createdAt).inMicroseconds / Duration.microsecondsPerHour;
  return hours < 0 ? 0 : hours;
}

WaitTone waitTone(double hours) {
  if (hours >= staleHours) return WaitTone.stale;
  return hours >= agingHours ? WaitTone.aging : WaitTone.fresh;
}

/// Título y pista de cada columna. Qué estados son columnas lo decide el servidor; aquí solo se
/// les da nombre en español. [fallback] es el nombre general del estado, para uno nuevo.
({String title, String hint}) columnText(String status, {required String fallback}) => switch (status) {
      'submitted' => (title: 'Recibidas', hint: 'Esperan clasificación'),
      'triaged' => (title: 'Clasificadas', hint: 'Esperan técnico'),
      'assigned' => (title: 'Asignadas', hint: 'Con técnico, sin iniciar'),
      _ => (title: fallback, hint: ''),
    };

/// Cómo se llama el movimiento a [status] en el menú «Mover a…»: las columnas con su nombre y
/// cancelar, que desde la bandeja es rechazar, como «Rechazar».
String moveLabel(String status, {required String fallback}) => status == 'cancelled' ? 'Rechazar' : columnText(status, fallback: fallback).title;

/// Etiqueta de categoría con la del catálogo; «Sin categoría» cuando no hay.
String categoryLabel(String? code, Map<String, String> names) {
  if (code == null || code.isEmpty || code == 'uncategorized') return 'Sin categoría';
  return names[code] ?? code;
}

/// Porcentaje de [part] sobre [whole], con un mínimo visible para valores no nulos.
double share(int part, int whole) {
  if (whole <= 0) return 0;
  final value = part / whole * 100;
  final minimum = part > 0 ? 4.0 : 0.0;
  return value < minimum ? minimum : value;
}

/// Posición de [code] entre las prioridades, de la más urgente (0) a la menos, repartida en
/// [tones] tonos. Un código desconocido usa el último. Ningún código va fijo.
int priorityTone(String code, List<PriorityOption> priorities, {int tones = 4}) {
  final ranked = [...priorities]..sort((a, b) => b.level.compareTo(a.level));
  final index = ranked.indexWhere((p) => p.code == code);
  if (index < 0) return tones - 1;
  final tone = index * tones ~/ ranked.length;
  return tone > tones - 1 ? tones - 1 : tone;
}

/// Nombre de una prioridad según la tabla del servidor; el código si no está.
String priorityName(String code, List<PriorityOption> priorities) {
  for (final priority in priorities) {
    if (priority.code == code) return priority.name;
  }
  return code;
}

/// Error del motivo de rechazo, en español, o `null` si es válido (sin contar espacios sobrantes,
/// igual que el backend).
String? reasonError(String? value) {
  final length = (value ?? '').trim().length;
  if (length == 0) return 'Escribe el motivo del rechazo.';
  if (length < minReasonLength) return 'El motivo debe tener al menos $minReasonLength caracteres.';
  if (length > maxReasonLength) return 'El motivo admite como máximo $maxReasonLength caracteres.';
  return null;
}

/// Error del rango «recibidas entre», o `null` si es válido: la inicial no es futura, la final no
/// es anterior a la inicial y como máximo 366 días. Las fechas se comparan por día.
String? queueRangeError(DateTime? from, DateTime? to, DateTime today) {
  DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
  final start = from == null ? null : day(from);
  final end = to == null ? null : day(to);
  if (start != null && start.isAfter(day(today))) return 'La fecha inicial no puede ser futura.';
  if (start != null && end != null) {
    if (end.isBefore(start)) return 'La fecha final no puede ser anterior a la inicial.';
    final days = DateTime.utc(end.year, end.month, end.day).difference(DateTime.utc(start.year, start.month, start.day)).inDays + 1;
    if (days > maxRangeDays) return 'El rango no puede superar $maxRangeDays días.';
  }
  return null;
}
