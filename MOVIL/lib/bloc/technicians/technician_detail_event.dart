part of 'technician_detail_bloc.dart';

sealed class TechnicianDetailEvent {
  const TechnicianDetailEvent();
}

/// Carga los indicadores y los tickets abiertos al abrir la ficha.
class TechnicianDetailRequested extends TechnicianDetailEvent {
  const TechnicianDetailRequested();
}

class TechnicianPerformanceRetried extends TechnicianDetailEvent {
  const TechnicianPerformanceRetried();
}

class TechnicianPerformancePeriodChanged extends TechnicianDetailEvent {
  const TechnicianPerformancePeriodChanged(this.period);
  final String period;
}

class TechnicianTicketsRetried extends TechnicianDetailEvent {
  const TechnicianTicketsRetried();
}
