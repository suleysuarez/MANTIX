/// Reglas del formulario de un plan de mantenimiento, portadas de la web (`plan-form.ts` y
/// `form-validation.ts`). El backend es la fuente de verdad: son los mismos límites.
library;

const planTitleMin = 3;
const planTitleMax = 200;
const planDescriptionMax = 2000;
const planIntervalMin = 1;
const planIntervalMax = 3650;
const planRemindMax = 365;
const planHoursMax = 999;

/// Días entre servicios y de antelación que propone el formulario.
const defaultIntervalDays = 30;
const defaultRemindDays = 3;

const _required = 'Este campo es obligatorio.';

/// Título obligatorio, de 3 a 200 caracteres sin contar espacios sobrantes.
String? planTitleError(String? value) {
  final length = (value ?? '').trim().length;
  if (length == 0) return _required;
  if (length < planTitleMin) return 'Debe tener al menos $planTitleMin caracteres.';
  if (length > planTitleMax) return 'Debe tener como máximo $planTitleMax caracteres.';
  return null;
}

/// Descripción opcional: vacía vale; si hay algo no puede ser solo espacios y respeta el máximo.
String? planDescriptionError(String? value) {
  final raw = value ?? '';
  if (raw.isEmpty) return null;
  if (raw.trim().isEmpty) return 'No puede contener solo espacios.';
  if (raw.trim().length > planDescriptionMax) return 'Debe tener como máximo $planDescriptionMax caracteres.';
  return null;
}

String? _integerError(String? value, int min, int max) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return _required;
  final number = int.tryParse(text);
  if (number == null) return 'Debe ser un número entero.';
  if (number < min) return 'Debe ser al menos $min.';
  if (number > max) return 'No puede ser mayor que $max.';
  return null;
}

/// Cada cuántos días: entero de 1 a 3650.
String? intervalError(String? value) => _integerError(value, planIntervalMin, planIntervalMax);

/// Días de antelación del recordatorio: entero de 0 a 365 que no supere el [interval] entre
/// servicios (si el intervalo es válido).
String? remindError(String? value, String? interval) {
  final problem = _integerError(value, 0, planRemindMax);
  if (problem != null) return problem;
  final days = int.parse(value!.trim());
  final every = int.tryParse((interval ?? '').trim());
  return every != null && days > every ? 'El recordatorio no puede superar el intervalo entre servicios.' : null;
}

/// Fecha y hora del primer servicio: obligatoria y no anterior a [now].
String? firstDueError(DateTime? value, DateTime now) {
  if (value == null) return _required;
  return value.isBefore(now) ? 'No se puede programar en el pasado.' : null;
}

final _decimal = RegExp(r'^\d+([.,]\d+)?$');

/// Horas opcionales (estimadas o reales): vacías valen; si hay algo, mayores que 0, hasta 999 y
/// con dos decimales como máximo. Admite coma o punto.
String? hoursError(String? value) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return null;
  if (!_decimal.hasMatch(text)) return 'Escribe un número válido.';
  final number = double.parse(text.replaceFirst(',', '.'));
  if (number <= 0) return 'Debe ser mayor que 0.';
  if (number > planHoursMax) return 'No puede ser mayor que $planHoursMax.';
  final separator = text.indexOf(RegExp('[.,]'));
  if (separator >= 0 && text.length - separator - 1 > 2) return 'Usa como máximo 2 decimales.';
  return null;
}

/// Las horas escritas como número; `null` si están vacías. Solo para un texto que ya pasó [hoursError].
double? parseHours(String? value) {
  final text = (value ?? '').trim();
  return text.isEmpty ? null : double.parse(text.replaceFirst(',', '.'));
}

/// «1,5 h» para las horas de un plan; «—» si no hay.
String formatPlanHours(double? hours) {
  if (hours == null) return '—';
  final text = hours.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'[.]$'), '');
  return '${text.replaceFirst('.', ',')} h';
}

/// «Cada 30 días».
String intervalText(int days) => days == 1 ? 'Cada día' : 'Cada $days días';

String _two(int value) => value.toString().padLeft(2, '0');

/// «26/11/2026 09:00 a. m.»: la fecha y hora del primer servicio como se escribe en el formulario.
String formatFormDateTime(DateTime date) {
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  return '${_two(date.day)}/${_two(date.month)}/${date.year} ${_two(hour)}:${_two(date.minute)} ${date.hour < 12 ? 'a. m.' : 'p. m.'}';
}

/// El primer servicio que propone el formulario: mañana a las 9:00.
DateTime defaultFirstDue(DateTime now) => DateTime(now.year, now.month, now.day + 1, 9);
