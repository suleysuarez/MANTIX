part of 'technician_detail_bloc.dart';

enum DetailBlockStatus { loading, ready, failure }

class TechnicianDetailState extends Equatable {
  const TechnicianDetailState({
    this.performanceStatus = DetailBlockStatus.loading,
    this.performance,
    this.period = '30d',
    this.performanceFailure,
    this.ticketsStatus = DetailBlockStatus.loading,
    this.tickets = const [],
    this.ticketsTotal = 0,
    this.ticketsFailure,
  });

  final DetailBlockStatus performanceStatus;

  /// `null` con el bloque listo significa que el servidor no dio indicadores de este técnico.
  final TechnicianPerformance? performance;

  /// Periodo de los indicadores, tal como lo devuelve el servidor (`30d`).
  final String period;
  final Failure? performanceFailure;

  final DetailBlockStatus ticketsStatus;

  /// Los tickets abiertos más recientes; [ticketsTotal] dice cuántos hay en total.
  final List<TicketListItem> tickets;
  final int ticketsTotal;
  final Failure? ticketsFailure;

  TechnicianDetailState copyWith({
    DetailBlockStatus? performanceStatus,
    TechnicianPerformance? performance,
    String? period,
    Failure? performanceFailure,
    DetailBlockStatus? ticketsStatus,
    List<TicketListItem>? tickets,
    int? ticketsTotal,
    Failure? ticketsFailure,
  }) =>
      TechnicianDetailState(
        performanceStatus: performanceStatus ?? this.performanceStatus,
        performance: performance ?? this.performance,
        period: period ?? this.period,
        performanceFailure: performanceFailure ?? this.performanceFailure,
        ticketsStatus: ticketsStatus ?? this.ticketsStatus,
        tickets: tickets ?? this.tickets,
        ticketsTotal: ticketsTotal ?? this.ticketsTotal,
        ticketsFailure: ticketsFailure ?? this.ticketsFailure,
      );

  @override
  List<Object?> get props => [performanceStatus, performance, period, performanceFailure, ticketsStatus, tickets, ticketsTotal, ticketsFailure];
}
