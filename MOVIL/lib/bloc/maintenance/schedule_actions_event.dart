part of 'schedule_actions_bloc.dart';

sealed class ScheduleActionsEvent {
  const ScheduleActionsEvent();
}

/// Programar un plan. Los campos numéricos llegan como el texto que escribió la persona (con coma
/// o punto en las horas); el Bloc los valida y los convierte. [equipmentId] es `null` si aún no se
/// eligió equipo; sin [technicianId], los recordatorios le llegan a quien lo programa.
class ScheduleCreateRequested extends ScheduleActionsEvent {
  const ScheduleCreateRequested({required this.equipmentId, required this.title, this.description, required this.intervalDays, required this.remindDays, required this.firstDueAt, this.estimatedHours, this.technicianId});

  final int? equipmentId;
  final String title;
  final String? description;
  final String intervalDays;
  final String remindDays;
  final DateTime? firstDueAt;
  final String? estimatedHours;
  final int? technicianId;
}

/// Marcar el servicio de [schedule] como hecho. [actualHours] son las horas reales, si se saben.
class ScheduleCompleteRequested extends ScheduleActionsEvent {
  const ScheduleCompleteRequested(this.schedule, {this.actualHours});

  final MaintenanceSchedule schedule;
  final String? actualHours;
}

/// Activar o desactivar [schedule].
class ScheduleActiveChangeRequested extends ScheduleActionsEvent {
  const ScheduleActiveChangeRequested(this.schedule, {required this.active});

  final MaintenanceSchedule schedule;
  final bool active;
}
