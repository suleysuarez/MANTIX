/// Respuestas de ejemplo de la API de técnicos, con la forma del backend.
library;

import 'package:dio/dio.dart';

import 'fakes.dart';
import 'requests_support.dart';

Map<String, Object?> technicianJson({
  int id = 5,
  String name = 'Luis Demo',
  String? email,
  String? code,
  String? specialization = 'Hardware',
  bool available = true,
  bool active = true,
  String? rate,
  int? userId,
}) =>
    {
      'id': id,
      'user_id': userId ?? id + 100,
      'full_name': name,
      'email': email ?? 'tech$id@demo.mantix.co',
      'employee_code': code,
      'specialization': specialization,
      'is_available': available,
      'is_active': active,
      'hourly_rate': rate,
      'created_at': '2026-10-01T10:00:00Z',
    };

/// `GET /dashboard/workload`: [loads] es id de técnico → (abiertos, resueltos).
Map<String, Object?> workloadJson(Map<int, (int, int)> loads, {int days = 30, String scope = 'all'}) => {
      'window_days': days,
      'scope': scope,
      'technicians': [
        for (final entry in loads.entries)
          {'technician_id': entry.key, 'full_name': 'Técnico ${entry.key}', 'is_available': true, 'open_tickets': entry.value.$1, 'resolved_in_window': entry.value.$2},
      ],
    };

Map<String, Object?> performanceRowJson({int id = 5, int open = 3, int resolved = 15, double? mttr = 12.5, bool lowSample = false, double? sla = 86.7, int slaN = 12, bool slaLow = false, int excluded = 3, int reopened = 1}) => {
      'technician_id': id,
      'full_name': 'Técnico $id',
      'specialization': 'Hardware',
      'is_available': true,
      'open_tickets': open,
      'resolved': resolved,
      'mttr_median_hours': mttr,
      'sample_size': resolved,
      'low_sample': lowSample,
      'sla_compliance_pct': sla,
      'sla_sample_size': slaN,
      'sla_low_sample': slaLow,
      'sla_excluded_no_sla': excluded,
      'reopened': reopened,
    };

Map<String, Object?> performanceJson(List<Map<String, Object?>> rows, {String period = '30d'}) => {
      'generated_at': '2026-11-11T12:00:00Z',
      'scope': 'all',
      'period': period,
      'window_start': '2026-10-12T12:00:00Z',
      'window_end': '2026-11-11T12:00:00Z',
      'technicians': rows,
    };

/// Responde las tres lecturas de la pantalla: técnicos, carga e indicadores. Un valor `null`
/// en [workload] o [performance] hace fallar esa lectura con un 500.
ResponseBody techniciansApi(RequestOptions options, {List<Map<String, Object?>> technicians = const [], Map<String, Object?>? workload, Map<String, Object?>? performance}) => switch (options.path) {
      '/technicians' => pagedResponse(technicians),
      '/dashboard/workload' => workload == null ? errorResponse(500) : jsonResponse(200, workload),
      '/dashboard/technicians' => performance == null ? errorResponse(500) : jsonResponse(200, performance),
      _ => errorResponse(404),
    };
