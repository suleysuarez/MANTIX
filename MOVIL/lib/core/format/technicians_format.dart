/// Reglas y formato de la pantalla de técnicos. Funciones puras, portadas de la web
/// (`technician-ui.ts`) para que ambas muestren lo mismo.
library;

import '../../models/technicians/technician_filters.dart';
import '../../models/technicians/technician_models.dart';

const maxSpecialization = 100;

/// `hourly_rate` es NUMERIC(10, 2) en la base de datos.
const maxRate = 99999999.99;

String statusLabel(TechnicianStatus status) => switch (status) {
      TechnicianStatus.free => 'Disponible',
      TechnicianStatus.busy => 'Con tickets activos',
      TechnicianStatus.unavailable => 'No disponible',
    };

String loadLabel(LoadBucket bucket) => switch (bucket) {
      LoadBucket.none => 'Sin tickets',
      LoadBucket.low => '1 a 2 tickets',
      LoadBucket.high => '3 o más tickets',
    };

String orderLabel(TechnicianOrder order) => switch (order) {
      TechnicianOrder.load => 'Menor carga de tickets',
      TechnicianOrder.availability => 'Disponibilidad',
      TechnicianOrder.resolved => 'Más tickets resueltos',
      TechnicianOrder.name => 'Nombre',
    };

/// Sin datos de carga ([workload] `null`) nadie cuenta como ocupado.
TechnicianStatus technicianStatus(Technician technician, Workload? workload) {
  if (!technician.isActive || !technician.isAvailable) return TechnicianStatus.unavailable;
  return (workload?.openOf(technician.id) ?? 0) > 0 ? TechnicianStatus.busy : TechnicianStatus.free;
}

/// «2 tickets activos» para quien está ocupado; el nombre del estado para los demás.
String statusText(Technician technician, Workload? workload) {
  final status = technicianStatus(technician, workload);
  if (status != TechnicianStatus.busy) return statusLabel(status);
  final open = workload!.openOf(technician.id);
  return '$open ${open == 1 ? 'ticket activo' : 'tickets activos'}';
}

LoadBucket loadBucket(int open) {
  if (open == 0) return LoadBucket.none;
  return open <= 2 ? LoadBucket.low : LoadBucket.high;
}

/// La especialización es un texto libre: «Hardware, Redes» son dos especialidades.
List<String> specialties(Technician technician) => [
      for (final part in (technician.specialization ?? '').split(RegExp('[,;]')))
        if (part.trim().isNotEmpty) part.trim(),
    ];

const _accented = 'áàäâãéèëêíìïîóòöôõúùüûñç';
const _plain = 'aaaaaeeeeiiiiooooouuuunc';

/// Minúsculas y sin tildes, para que «sofia» encuentre a «Sofía».
String normalize(String value) {
  final lower = value.toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    final index = _accented.indexOf(char);
    buffer.write(index < 0 ? char : _plain[index]);
  }
  return buffer.toString();
}

int _byText(String a, String b) => normalize(a).compareTo(normalize(b));

/// Todas las especialidades, sin repetir (sin distinguir tildes ni mayúsculas) y en orden.
List<String> allSpecialties(Iterable<Technician> technicians) {
  final seen = <String, String>{};
  for (final technician in technicians) {
    for (final item in specialties(technician)) {
      seen.putIfAbsent(normalize(item), () => item);
    }
  }
  return seen.values.toList()..sort(_byText);
}

/// Filtra y ordena los técnicos (la lista es corta: se hace en la app, como en la web).
/// [pinnedId] sale siempre primero: es el técnico recién registrado.
List<Technician> filterTechnicians(Iterable<Technician> technicians, Workload? workload, TechnicianFilters filters, {TechnicianOrder order = TechnicianOrder.load, int? pinnedId}) {
  final query = normalize(filters.search.trim());
  int open(Technician t) => workload?.openOf(t.id) ?? 0;
  int resolved(Technician t) => workload?.resolvedOf(t.id) ?? 0;

  final matches = technicians.where((technician) {
    if (filters.status != null && technicianStatus(technician, workload) != filters.status) return false;
    if (filters.specialties.isNotEmpty && !specialties(technician).any((item) => filters.specialties.contains(normalize(item)))) return false;
    if (filters.accounts.isNotEmpty && !filters.accounts.contains(technician.isActive)) return false;
    if (filters.availability.isNotEmpty && !filters.availability.contains(technician.isAvailable)) return false;
    if (filters.loads.isNotEmpty && !filters.loads.contains(loadBucket(open(technician)))) return false;
    if (query.isEmpty) return true;
    final haystack = normalize([technician.fullName, technician.email, technician.employeeCode ?? '', technician.specialization ?? ''].join(' '));
    return haystack.contains(query);
  }).toList();

  int byName(Technician a, Technician b) => _byText(a.fullName, b.fullName);
  int orElseName(int result, Technician a, Technician b) => result != 0 ? result : byName(a, b);
  final compare = switch (order) {
    TechnicianOrder.load => (Technician a, Technician b) => orElseName(open(a) - open(b), a, b),
    TechnicianOrder.availability => (Technician a, Technician b) => orElseName(technicianStatus(a, workload).index - technicianStatus(b, workload).index, a, b),
    TechnicianOrder.resolved => (Technician a, Technician b) => orElseName(resolved(b) - resolved(a), a, b),
    TechnicianOrder.name => byName,
  };
  matches.sort((a, b) {
    if (a.id == pinnedId) return b.id == pinnedId ? 0 : -1;
    if (b.id == pinnedId) return 1;
    return compare(a, b);
  });
  return matches;
}

TechnicianSummary summarize(Iterable<Technician> technicians, Workload? workload) {
  var total = 0, available = 0, busy = 0, unavailable = 0, openTickets = 0, resolved = 0, overloaded = 0;
  final people = technicians.toList();
  final assignable = people.where((t) => t.isActive && t.isAvailable).toList();
  final average = assignable.isEmpty || workload == null ? 0.0 : assignable.fold<int>(0, (sum, t) => sum + workload.openOf(t.id)) / assignable.length;
  for (final technician in people) {
    total++;
    final status = technicianStatus(technician, workload);
    if (status == TechnicianStatus.unavailable) {
      unavailable++;
    } else {
      available++;
      if (status == TechnicianStatus.busy) busy++;
    }
    final open = workload?.openOf(technician.id) ?? 0;
    if (technician.isActive && technician.isAvailable && workload != null && open > average) overloaded++;
    openTickets += open;
    resolved += workload?.resolvedOf(technician.id) ?? 0;
  }
  return TechnicianSummary(total: total, available: available, busy: busy, unavailable: unavailable, openTickets: openTickets, resolved: resolved, overloaded: overloaded);
}

/// Error de la especialización, o `null` si es válida (sin contar espacios sobrantes).
String? specializationError(String? value) =>
    (value ?? '').trim().length > maxSpecialization ? 'La especialización no puede superar los $maxSpecialization caracteres.' : null;

final _rate = RegExp(r'^\d+([.,]\d+)?$');

/// Error de la tarifa por hora, o `null` si es válida. Vacía es válida (sin tarifa). Admite coma
/// o punto como separador decimal, dos decimales como máximo y ningún negativo.
String? rateError(String? value) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return null;
  if (!_rate.hasMatch(text)) return 'La tarifa por hora debe ser un número igual o mayor a cero.';
  final separator = text.indexOf(RegExp('[.,]'));
  if (separator >= 0 && text.length - separator - 1 > 2) return 'La tarifa por hora admite como máximo dos decimales.';
  if (double.parse(text.replaceFirst(',', '.')) > maxRate) return 'La tarifa por hora supera el máximo permitido.';
  return null;
}

/// La tarifa escrita por la persona como número; `null` si está vacía. Solo para un texto que
/// ya pasó [rateError].
double? parseRate(String? value) {
  final text = (value ?? '').trim();
  return text.isEmpty ? null : double.parse(text.replaceFirst(',', '.'));
}

/// «$35,00»: dos decimales con coma, como el resto de la app; «—» sin tarifa.
String formatRate(double? rate) => rate == null ? '—' : '\$${rate.toStringAsFixed(2).replaceFirst('.', ',')}';

/// La tarifa para volver a editarla: «35,5» → «35,50»; vacío sin tarifa.
String rateInput(double? rate) => rate == null ? '' : rate.toStringAsFixed(2).replaceFirst('.', ',');
