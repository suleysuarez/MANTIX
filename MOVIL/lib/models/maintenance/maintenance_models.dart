import 'package:equatable/equatable.dart';

import '../requests/request_models.dart';

DateTime? _date(Object? value) => value is String ? DateTime.tryParse(value)?.toLocal() : null;

double? _double(Object? value) => switch (value) {
      final num number => number.toDouble(),
      final String text => double.tryParse(text),
      _ => null,
    };

/// Técnico responsable de un plan, tal como lo resume la API (`technician` de un plan).
class ScheduleTechnician extends Equatable {
  const ScheduleTechnician({required this.id, required this.fullName, this.userId});

  factory ScheduleTechnician.fromJson(Map<String, Object?> json) => ScheduleTechnician(
        id: json['id']! as int,
        userId: json['user_id'] as int?,
        fullName: json['full_name']! as String,
      );

  final int id;
  final int? userId;
  final String fullName;

  @override
  List<Object?> get props => [id, userId, fullName];
}

/// Estado de un plan: inactivo manda sobre vencido, y vencido sobre programado.
enum ScheduleState { planned, overdue, inactive }

/// Plan de mantenimiento preventivo (`GET /maintenance/schedules`): un servicio recurrente de un
/// equipo. Las fechas ya vienen en hora local.
class MaintenanceSchedule extends Equatable {
  const MaintenanceSchedule({
    required this.id,
    required this.equipment,
    required this.title,
    required this.intervalDays,
    required this.remindDaysBefore,
    required this.nextDueAt,
    this.technician,
    this.description,
    this.estimatedHours,
    this.lastRemindedAt,
    this.isActive = true,
    this.createdAt,
  });

  factory MaintenanceSchedule.fromJson(Map<String, Object?> json) => MaintenanceSchedule(
        id: json['id']! as int,
        equipment: EquipmentRef.fromJson((json['equipment']! as Map).cast<String, Object?>()),
        technician: json['technician'] is Map ? ScheduleTechnician.fromJson((json['technician']! as Map).cast<String, Object?>()) : null,
        title: json['title']! as String,
        description: json['description'] as String?,
        intervalDays: json['interval_days']! as int,
        estimatedHours: _double(json['estimated_hours']),
        remindDaysBefore: json['remind_days_before']! as int,
        nextDueAt: _date(json['next_due_at'])!,
        lastRemindedAt: _date(json['last_reminded_at']),
        isActive: json['is_active'] as bool? ?? true,
        createdAt: _date(json['created_at']),
      );

  final int id;
  final EquipmentRef equipment;
  final ScheduleTechnician? technician;
  final String title;
  final String? description;

  /// Días entre un servicio y el siguiente.
  final int intervalDays;
  final double? estimatedHours;

  /// Con cuántos días de antelación se avisa de cada servicio.
  final int remindDaysBefore;
  final DateTime nextDueAt;
  final DateTime? lastRemindedAt;
  final bool isActive;
  final DateTime? createdAt;

  ScheduleState stateAt(DateTime now) {
    if (!isActive) return ScheduleState.inactive;
    return nextDueAt.isBefore(now) ? ScheduleState.overdue : ScheduleState.planned;
  }

  @override
  List<Object?> get props => [id, equipment, technician, title, description, intervalDays, estimatedHours, remindDaysBefore, nextDueAt, lastRemindedAt, isActive, createdAt];
}

/// `planned`: servicio por hacer; `overdue`: ya pasó su fecha sin hacerse; `done`: ya hecho.
enum CalendarKind { planned, overdue, done }

/// Un servicio en el calendario (`GET /maintenance/calendar`).
class CalendarEvent extends Equatable {
  const CalendarEvent({required this.kind, required this.scheduleId, required this.title, required this.equipmentId, required this.assetTag, required this.at, this.technician, this.completedAt, this.onTime});

  factory CalendarEvent.fromJson(Map<String, Object?> json) => CalendarEvent(
        kind: switch (json['kind']) {
          'overdue' => CalendarKind.overdue,
          'done' => CalendarKind.done,
          _ => CalendarKind.planned,
        },
        scheduleId: json['schedule_id']! as int,
        title: json['title']! as String,
        equipmentId: json['equipment_id']! as int,
        assetTag: json['asset_tag']! as String,
        technician: json['technician'] as String?,
        at: _date(json['at'])!,
        completedAt: _date(json['completed_at']),
        onTime: json['on_time'] as bool?,
      );

  final CalendarKind kind;
  final int scheduleId;
  final String title;
  final int equipmentId;
  final String assetTag;

  /// Nombre del técnico, o `null` si el plan no tiene uno.
  final String? technician;

  /// La fecha de este servicio.
  final DateTime at;
  final DateTime? completedAt;

  /// Solo en los servicios hechos.
  final bool? onTime;

  @override
  List<Object?> get props => [kind, scheduleId, title, equipmentId, assetTag, technician, at, completedAt, onTime];
}

/// Los servicios de un rango. [truncated] avisa de que se llegó al tope del servidor.
class CalendarData extends Equatable {
  const CalendarData({required this.events, this.truncated = false});

  factory CalendarData.fromJson(Map<String, Object?> json) {
    final events = json['events'];
    return CalendarData(
      events: [if (events is List) for (final item in events.whereType<Map>()) CalendarEvent.fromJson(item.cast<String, Object?>())],
      truncated: json['truncated'] as bool? ?? false,
    );
  }

  final List<CalendarEvent> events;
  final bool truncated;

  @override
  List<Object?> get props => [events, truncated];
}

/// Un servicio hecho de un plan.
class ScheduleRun extends Equatable {
  const ScheduleRun({required this.id, required this.dueAt, required this.completedAt, required this.onTime, this.actualHours});

  factory ScheduleRun.fromJson(Map<String, Object?> json) => ScheduleRun(
        id: json['id']! as int,
        dueAt: _date(json['due_at'])!,
        completedAt: _date(json['completed_at'])!,
        onTime: json['on_time'] as bool? ?? true,
        actualHours: _double(json['actual_hours']),
      );

  final int id;
  final DateTime dueAt;
  final DateTime completedAt;
  final bool onTime;
  final double? actualHours;

  @override
  List<Object?> get props => [id, dueAt, completedAt, onTime, actualHours];
}

/// Un cambio de la fecha de un plan.
class ScheduleReschedule extends Equatable {
  const ScheduleReschedule({required this.id, required this.oldDueAt, required this.newDueAt, required this.changedAt, this.reason});

  factory ScheduleReschedule.fromJson(Map<String, Object?> json) => ScheduleReschedule(
        id: json['id']! as int,
        oldDueAt: _date(json['old_due_at'])!,
        newDueAt: _date(json['new_due_at'])!,
        reason: json['reason'] as String?,
        changedAt: _date(json['changed_at'])!,
      );

  final int id;
  final DateTime oldDueAt;
  final DateTime newDueAt;
  final String? reason;
  final DateTime changedAt;

  @override
  List<Object?> get props => [id, oldDueAt, newDueAt, reason, changedAt];
}

class ScheduleHistory extends Equatable {
  const ScheduleHistory({this.runs = const [], this.reschedules = const []});

  factory ScheduleHistory.fromJson(Map<String, Object?> json) {
    List<T> list<T>(Object? data, T Function(Map<String, Object?>) parse) => [if (data is List) for (final item in data.whereType<Map>()) parse(item.cast<String, Object?>())];
    return ScheduleHistory(runs: list(json['runs'], ScheduleRun.fromJson), reschedules: list(json['reschedules'], ScheduleReschedule.fromJson));
  }

  final List<ScheduleRun> runs;
  final List<ScheduleReschedule> reschedules;

  @override
  List<Object?> get props => [runs, reschedules];
}

/// Filtro de estado de la lista de planes.
enum ScheduleStatusFilter { all, overdue, active, inactive }
