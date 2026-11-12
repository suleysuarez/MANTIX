/// Filtros, orden y cifras de la pantalla de técnicos. Las reglas que los aplican están en
/// `core/format/technicians_format.dart`.
library;

import 'package:equatable/equatable.dart';

/// Estado operativo derivado: disponibilidad del perfil y tickets abiertos asignados.
enum TechnicianStatus { free, busy, unavailable }

/// Tickets abiertos: ninguno, 1 a 2, o 3 o más.
enum LoadBucket { none, low, high }

/// [load] (menos tickets abiertos primero) es el orden por defecto: sirve para repartir
/// trabajo, no para comparar desempeño.
enum TechnicianOrder { load, availability, resolved, name }

/// Filtros de la lista. Un conjunto vacío no filtra; con varios valores basta coincidir con uno.
class TechnicianFilters extends Equatable {
  const TechnicianFilters({this.search = '', this.status, this.specialties = const {}, this.accounts = const {}, this.availability = const {}, this.loads = const {}});

  final String search;

  /// Lo que ponen las tarjetas de resumen: disponibilidad y carga combinadas.
  final TechnicianStatus? status;

  /// Especialidades, ya normalizadas (minúsculas y sin tildes).
  final Set<String> specialties;

  /// Cuenta de usuario: `true` activa, `false` inactiva.
  final Set<bool> accounts;

  /// Disponibilidad del perfil: `true` disponible, `false` no disponible.
  final Set<bool> availability;
  final Set<LoadBucket> loads;

  /// Filtros de la hoja que están puestos (sin contar la búsqueda ni la tarjeta de resumen).
  int get activeCount => [specialties, accounts, availability, loads].where((group) => group.isNotEmpty).length;

  bool get isEmpty => search.trim().isEmpty && status == null && activeCount == 0;

  TechnicianFilters copyWith({String? search, TechnicianStatus? status, bool clearStatus = false, Set<String>? specialties, Set<bool>? accounts, Set<bool>? availability, Set<LoadBucket>? loads}) => TechnicianFilters(
        search: search ?? this.search,
        status: clearStatus ? null : (status ?? this.status),
        specialties: specialties ?? this.specialties,
        accounts: accounts ?? this.accounts,
        availability: availability ?? this.availability,
        loads: loads ?? this.loads,
      );

  @override
  List<Object?> get props => [search, status, specialties, accounts, availability, loads];
}

/// Cifras de las tarjetas de resumen. [available] cuenta a todos los disponibles, con o sin
/// tickets; los libres son [free].
class TechnicianSummary extends Equatable {
  const TechnicianSummary({this.total = 0, this.available = 0, this.busy = 0, this.unavailable = 0, this.openTickets = 0, this.resolved = 0, this.overloaded = 0});

  final int total;
  final int available;
  final int busy;
  final int unavailable;
  final int openTickets;
  final int resolved;
  final int overloaded;

  int get free => available - busy;

  @override
  List<Object?> get props => [total, available, busy, unavailable, openTickets, resolved, overloaded];
}
