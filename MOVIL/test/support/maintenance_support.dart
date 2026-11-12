/// Respuestas de ejemplo de la API de mantenimiento preventivo, con la forma del backend.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:mantix/models/maintenance/maintenance_models.dart';

import 'fakes.dart';

Map<String, Object?> scheduleJson({
  int id = 4,
  String title = 'Revisión de UPS',
  String tag = 'SRV-0003',
  Map<String, Object?>? technician = const {'id': 2, 'user_id': 8, 'full_name': 'Luis Mora'},
  bool active = true,
  String due = '2026-12-01T15:00:00Z',
  int interval = 30,
  int remind = 3,
  String? hours = '1.50',
  String? description = 'Limpiar filtros',
}) =>
    {
      'id': id,
      'equipment': {'id': 12, 'asset_tag': tag, 'brand': 'Dell', 'model': 'PowerEdge'},
      'technician': technician,
      'title': title,
      'description': description,
      'interval_days': interval,
      'estimated_hours': hours,
      'remind_days_before': remind,
      'next_due_at': due,
      'last_reminded_at': null,
      'is_active': active,
      'created_at': '2026-10-01T10:00:00Z',
    };

Map<String, Object?> calendarEventJson({String kind = 'planned', int id = 4, String title = 'Revisión de UPS', String at = '2026-10-25T15:00:00Z', String tag = 'SRV-0003', String? technician = 'Luis Mora', bool? onTime}) => {
      'kind': kind,
      'schedule_id': id,
      'title': title,
      'equipment_id': 12,
      'asset_tag': tag,
      'technician': technician,
      'at': at,
      'completed_at': kind == 'done' ? at : null,
      'on_time': kind == 'done' ? (onTime ?? true) : null,
    };

Map<String, Object?> calendarJson(List<Map<String, Object?>> events, {bool truncated = false}) => {
      'generated_at': '2026-10-25T12:00:00Z',
      'start': '2026-09-28T05:00:00Z',
      'end': '2026-11-02T05:00:00Z',
      'truncated': truncated,
      'events': events,
    };

Map<String, Object?> historyJson({List<Map<String, Object?>>? runs, List<Map<String, Object?>>? reschedules}) => {
      'runs': runs ?? [
        {'id': 1, 'due_at': '2026-09-25T15:00:00Z', 'completed_at': '2026-09-26T15:00:00Z', 'on_time': false, 'actual_hours': '2.00'},
      ],
      'reschedules': reschedules ?? [
        {'id': 1, 'old_due_at': '2026-10-25T15:00:00Z', 'new_due_at': '2026-11-02T15:00:00Z', 'reason': 'Equipo en uso', 'changed_at': '2026-10-20T12:00:00Z'},
      ],
    };

CalendarEvent calendarEvent({CalendarKind kind = CalendarKind.planned, int id = 1, String title = 'Servicio', required DateTime at, bool? onTime}) =>
    CalendarEvent(kind: kind, scheduleId: id, title: title, equipmentId: 12, assetTag: 'SRV-0003', at: at, onTime: onTime);

/// Un adaptador que deja cada petición esperando hasta que la prueba la libera: sirve para probar
/// qué pasa con una respuesta que llega tarde.
class GatedAdapter implements HttpClientAdapter {
  GatedAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final List<RequestOptions> requests = [];
  final List<Completer<void>> _gates = [];

  /// Peticiones que esperan su respuesta.
  int get pending => _gates.length;

  /// Responde a la petición más antigua que espera.
  void releaseNext() => _gates.removeAt(0).complete();

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final gate = Completer<void>();
    _gates.add(gate);
    await gate.future;
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

/// Respuesta con el cuerpo de [calendarJson] sin tocar el adaptador (para los `handler`).
ResponseBody calendarResponse(List<Map<String, Object?>> events, {bool truncated = false}) => jsonResponse(200, calendarJson(events, truncated: truncated));
