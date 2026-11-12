import 'dart:async';

import 'package:dio/dio.dart';

import '../../core/errors/failure_mapper.dart';
import '../../models/maintenance/maintenance_models.dart';
import '../../models/page_info.dart';

/// Acceso a la API de mantenimiento preventivo: calendario, planes, su historial y los cambios.
/// Cualquier error de red o de servidor sale como un `Failure` ya traducido. Cada cambio avisa por
/// [changes] para que el calendario y las listas abiertas se recarguen sin acoplarse a quien lo
/// hizo.
class MaintenanceRepository {
  MaintenanceRepository(this._dio);

  final Dio _dio;
  final _changes = StreamController<void>.broadcast();

  /// Emite después de programar, completar, desactivar o activar un plan.
  Stream<void> get changes => _changes.stream;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (error) {
      throw mapDioException(error);
    }
  }

  static String? _hours(double? value) => value?.toStringAsFixed(2);

  /// Los servicios de `[start, end)` (requiere `mantenimiento:ver`). El servidor admite como máximo
  /// 62 días; quien solo ve lo asignado recibe solo sus planes.
  Future<CalendarData> calendar(DateTime start, DateTime end) => _guard(() async {
        final response = await _dio.get<Map<String, Object?>>('/maintenance/calendar', queryParameters: {
          'start': start.toUtc().toIso8601String(),
          'end': end.toUtc().toIso8601String(),
        });
        return CalendarData.fromJson(response.data!);
      });

  /// Planes por páginas (requiere `mantenimiento:ver`). [status] `overdue` pide solo los activos
  /// ya vencidos; [sort] admite `next_due_at` (por defecto), `title` y `created_at`, con `-` delante
  /// para invertir.
  Future<PagedResult<MaintenanceSchedule>> schedules({int page = 1, int size = PageInfo.defaultPageSize, String? search, int? technicianId, ScheduleStatusFilter status = ScheduleStatusFilter.all, String sort = 'next_due_at'}) => _guard(() async {
        final term = search?.trim();
        final response = await _dio.get<Object?>('/maintenance/schedules', queryParameters: {
          'page': page,
          'size': size,
          'sort': sort,
          if (term != null && term.isNotEmpty) 'search': term,
          'technician_id': ?technicianId,
          if (status == ScheduleStatusFilter.overdue) 'overdue': true,
          if (status == ScheduleStatusFilter.active) 'is_active': true,
          if (status == ScheduleStatusFilter.inactive) 'is_active': false,
        });
        final data = response.data;
        return PagedResult(
          items: [if (data is List) for (final item in data) MaintenanceSchedule.fromJson((item as Map).cast<String, Object?>())],
          info: PageInfo.fromHeaders(response.headers),
        );
      });

  Future<MaintenanceSchedule> schedule(int id) => _guard(() async {
        final response = await _dio.get<Map<String, Object?>>('/maintenance/schedules/$id');
        return MaintenanceSchedule.fromJson(response.data!);
      });

  /// Servicios hechos y cambios de fecha de un plan.
  Future<ScheduleHistory> history(int id) => _guard(() async {
        final response = await _dio.get<Map<String, Object?>>('/maintenance/schedules/$id/history');
        return ScheduleHistory.fromJson(response.data!);
      });

  /// Programa un plan (requiere `mantenimiento:crear`). Sin [technicianId], los recordatorios le
  /// llegan a quien lo crea.
  Future<MaintenanceSchedule> create({required int equipmentId, required String title, String? description, required int intervalDays, required int remindDaysBefore, required DateTime firstDueAt, double? estimatedHours, int? technicianId}) => _guard(() async {
        final response = await _dio.post<Map<String, Object?>>('/maintenance/schedules', data: {
          'equipment_id': equipmentId,
          'technician_id': ?technicianId,
          'title': title,
          'description': description,
          'interval_days': intervalDays,
          'estimated_hours': _hours(estimatedHours),
          'remind_days_before': remindDaysBefore,
          'first_due_at': firstDueAt.toUtc().toIso8601String(),
        });
        _changes.add(null);
        return MaintenanceSchedule.fromJson(response.data!);
      });

  /// Marca el servicio como hecho y adelanta la fecha un intervalo (requiere `mantenimiento:editar`).
  /// [actualHours] son las horas que de verdad llevó, si se sabe.
  Future<MaintenanceSchedule> complete(int id, {double? actualHours}) => _guard(() async {
        final response = await _dio.post<Map<String, Object?>>('/maintenance/schedules/$id/complete', data: {'actual_hours': _hours(actualHours)});
        _changes.add(null);
        return MaintenanceSchedule.fromJson(response.data!);
      });

  /// Activa o desactiva un plan (requiere `mantenimiento:editar`).
  Future<MaintenanceSchedule> setActive(int id, {required bool active}) => _guard(() async {
        final response = await _dio.patch<Map<String, Object?>>('/maintenance/schedules/$id', data: {'is_active': active});
        _changes.add(null);
        return MaintenanceSchedule.fromJson(response.data!);
      });
}
