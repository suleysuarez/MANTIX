part of 'technicians_list_bloc.dart';

enum TechniciansStatus { loading, ready, failure }

class TechniciansListState extends Equatable {
  const TechniciansListState({
    this.status = TechniciansStatus.loading,
    this.technicians = const [],
    this.workload,
    this.failure,
    this.workloadFailure,
    this.filters = const TechnicianFilters(),
    this.order = TechnicianOrder.load,
    this.page = 1,
    this.pageSize = PageInfo.defaultPageSize,
    this.pinnedId,
  });

  final TechniciansStatus status;

  /// Todos los técnicos recibidos; siguen visibles mientras se recarga o si la recarga falla.
  final List<Technician> technicians;

  /// `null` si la carga no se pudo leer (o aún no llegó): los indicadores no están disponibles.
  final Workload? workload;
  final Failure? failure;
  final Failure? workloadFailure;
  final TechnicianFilters filters;
  final TechnicianOrder order;

  /// Base 1.
  final int page;
  final int pageSize;

  /// Técnico recién registrado: sale primero hasta que cambian los filtros o el orden.
  final int? pinnedId;

  /// Aún no hay nada que enseñar.
  bool get initialLoading => status == TechniciansStatus.loading && technicians.isEmpty;

  /// Se muestra el error con reintento solo si no hay lista que enseñar.
  bool get unavailable => status == TechniciansStatus.failure && technicians.isEmpty;

  bool get hasWorkload => workload != null;

  List<Technician> get filtered => filterTechnicians(technicians, workload, filters, order: order, pinnedId: pinnedId);

  int get totalPages {
    final pages = (filtered.length / pageSize).ceil();
    return pages < 1 ? 1 : pages;
  }

  /// Los técnicos de la página actual.
  List<Technician> get pageItems => filtered.skip((page - 1) * pageSize).take(pageSize).toList();

  /// Cifras de las tarjetas, sobre todos los técnicos (no solo los filtrados).
  TechnicianSummary get summary => summarize(technicians, workload);

  List<String> get specialties => allSpecialties(technicians);

  TechniciansListState copyWith({
    TechniciansStatus? status,
    List<Technician>? technicians,
    Workload? workload,
    bool clearWorkload = false,
    Failure? failure,
    bool clearFailure = false,
    Failure? workloadFailure,
    bool clearWorkloadFailure = false,
    TechnicianFilters? filters,
    TechnicianOrder? order,
    int? page,
    int? pageSize,
    int? pinnedId,
    bool clearPinned = false,
  }) =>
      TechniciansListState(
        status: status ?? this.status,
        technicians: technicians ?? this.technicians,
        workload: clearWorkload ? null : (workload ?? this.workload),
        failure: clearFailure ? null : (failure ?? this.failure),
        workloadFailure: clearWorkloadFailure ? null : (workloadFailure ?? this.workloadFailure),
        filters: filters ?? this.filters,
        order: order ?? this.order,
        page: page ?? this.page,
        pageSize: pageSize ?? this.pageSize,
        pinnedId: clearPinned ? null : (pinnedId ?? this.pinnedId),
      );

  @override
  List<Object?> get props => [status, technicians, workload, failure, workloadFailure, filters, order, page, pageSize, pinnedId];
}
