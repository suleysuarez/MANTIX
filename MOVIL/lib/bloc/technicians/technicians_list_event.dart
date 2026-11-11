part of 'technicians_list_bloc.dart';

sealed class TechniciansListEvent {
  const TechniciansListEvent();
}

/// Carga o recarga los técnicos y su carga (al abrir, al tirar para refrescar, al reintentar o
/// tras un cambio).
class TechniciansRequested extends TechniciansListEvent {
  const TechniciansRequested({this.done});

  /// Se completa cuando termina la carga (tirar para refrescar espera a esto).
  final Completer<void>? done;
}

class TechniciansSearchChanged extends TechniciansListEvent {
  const TechniciansSearchChanged(this.search);

  final String search;
}

/// Filtros nuevos (la hoja de filtros, una tarjeta de resumen o quitar un chip).
class TechniciansFiltersChanged extends TechniciansListEvent {
  const TechniciansFiltersChanged(this.filters);

  final TechnicianFilters filters;
}

class TechniciansOrderChanged extends TechniciansListEvent {
  const TechniciansOrderChanged(this.order);

  final TechnicianOrder order;
}

class TechniciansPageChanged extends TechniciansListEvent {
  const TechniciansPageChanged(this.page);

  final int page;
}

class TechniciansPageSizeChanged extends TechniciansListEvent {
  const TechniciansPageSizeChanged(this.pageSize);

  final int pageSize;
}

/// Se acaba de registrar [technician]: la lista vuelve a la página 1, sin filtros, con él de
/// primero.
class TechnicianCreatedShown extends TechniciansListEvent {
  const TechnicianCreatedShown(this.technician);

  final Technician technician;
}
