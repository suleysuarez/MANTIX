part of 'schedule_detail_bloc.dart';

sealed class ScheduleDetailEvent {
  const ScheduleDetailEvent();
}

/// Carga el plan y su historial al abrir la ficha.
class ScheduleDetailRequested extends ScheduleDetailEvent {
  const ScheduleDetailRequested();
}

class SchedulePlanRetried extends ScheduleDetailEvent {
  const SchedulePlanRetried();
}

class ScheduleHistoryRetried extends ScheduleDetailEvent {
  const ScheduleHistoryRetried();
}
