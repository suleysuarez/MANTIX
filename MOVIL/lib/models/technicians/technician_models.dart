import 'package:equatable/equatable.dart';

double? _double(Object? value) => switch (value) {
      final num number => number.toDouble(),
      final String text => double.tryParse(text),
      _ => null,
    };

/// Perfil de técnico (`GET /technicians`). [isActive] es el estado de la cuenta del usuario y
/// [isAvailable] la disponibilidad del perfil. [hourlyRate] solo llega a quien tiene
/// `tecnicos:editar`; para los demás es `null`.
class Technician extends Equatable {
  const Technician({
    required this.id,
    required this.fullName,
    this.userId,
    this.email = '',
    this.employeeCode,
    this.specialization,
    this.isActive = true,
    this.isAvailable = true,
    this.hourlyRate,
    this.createdAt,
  });

  factory Technician.fromJson(Map<String, Object?> json) => Technician(
        id: json['id']! as int,
        userId: json['user_id'] as int?,
        fullName: json['full_name']! as String,
        email: (json['email'] as String?) ?? '',
        employeeCode: json['employee_code'] as String?,
        specialization: json['specialization'] as String?,
        // Una lista sin el dato (servidor antiguo) cuenta como cuenta activa, igual que la web.
        isActive: json['is_active'] as bool? ?? true,
        isAvailable: json['is_available'] as bool? ?? true,
        hourlyRate: _double(json['hourly_rate']),
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      );

  final int id;
  final int? userId;
  final String fullName;
  final String email;
  final String? employeeCode;
  final String? specialization;
  final bool isActive;
  final bool isAvailable;
  final double? hourlyRate;
  final DateTime? createdAt;

  @override
  List<Object?> get props => [id, userId, fullName, email, employeeCode, specialization, isActive, isAvailable, hourlyRate, createdAt];
}

/// Carga de un técnico en la ventana pedida (`GET /dashboard/workload`).
class TechnicianLoad extends Equatable {
  const TechnicianLoad({required this.technicianId, this.openTickets = 0, this.resolved = 0});

  factory TechnicianLoad.fromJson(Map<String, Object?> json) => TechnicianLoad(
        technicianId: json['technician_id']! as int,
        openTickets: json['open_tickets'] as int? ?? 0,
        resolved: json['resolved_in_window'] as int? ?? 0,
      );

  final int technicianId;

  /// Tickets asignados y aún abiertos, ahora.
  final int openTickets;

  /// Tickets que resolvió dentro de la ventana.
  final int resolved;

  @override
  List<Object?> get props => [technicianId, openTickets, resolved];
}

/// Carga de todos los técnicos que el servidor deja ver. Quien no ve toda la operación
/// (`scope == 'own'`) solo recibe su propia fila.
class Workload extends Equatable {
  const Workload({required this.windowDays, required this.byTechnician, this.scope = 'all'});

  factory Workload.fromJson(Map<String, Object?> json) {
    final rows = json['technicians'];
    return Workload(
      windowDays: json['window_days'] as int? ?? 30,
      scope: json['scope'] as String? ?? 'all',
      byTechnician: {
        if (rows is List)
          for (final row in rows.whereType<Map>()) row['technician_id'] as int: TechnicianLoad.fromJson(row.cast<String, Object?>()),
      },
    );
  }

  final int windowDays;
  final String scope;
  final Map<int, TechnicianLoad> byTechnician;

  int openOf(int technicianId) => byTechnician[technicianId]?.openTickets ?? 0;
  int resolvedOf(int technicianId) => byTechnician[technicianId]?.resolved ?? 0;

  @override
  List<Object?> get props => [windowDays, scope, byTechnician];
}

/// Indicadores de un técnico en el periodo (`GET /dashboard/technicians`). «Pocos datos»
/// ([lowSample], [slaLowSample]: 0 < n < 5) y el SLA sin las prioridades que no tienen tiempo
/// definido ([slaExcludedNoSla]) los decide el servidor; la app solo los muestra.
class TechnicianPerformance extends Equatable {
  const TechnicianPerformance({
    required this.technicianId,
    this.openTickets = 0,
    this.resolved = 0,
    this.mttrMedianHours,
    this.sampleSize = 0,
    this.lowSample = false,
    this.slaCompliancePct,
    this.slaSampleSize = 0,
    this.slaLowSample = false,
    this.slaExcludedNoSla = 0,
    this.reopened = 0,
  });

  factory TechnicianPerformance.fromJson(Map<String, Object?> json) => TechnicianPerformance(
        technicianId: json['technician_id']! as int,
        openTickets: json['open_tickets'] as int? ?? 0,
        resolved: json['resolved'] as int? ?? 0,
        mttrMedianHours: _double(json['mttr_median_hours']),
        sampleSize: json['sample_size'] as int? ?? 0,
        lowSample: json['low_sample'] as bool? ?? false,
        slaCompliancePct: _double(json['sla_compliance_pct']),
        slaSampleSize: json['sla_sample_size'] as int? ?? 0,
        slaLowSample: json['sla_low_sample'] as bool? ?? false,
        slaExcludedNoSla: json['sla_excluded_no_sla'] as int? ?? 0,
        reopened: json['reopened'] as int? ?? 0,
      );

  final int technicianId;
  final int openTickets;
  final int resolved;

  /// Mediana de horas entre crear y resolver; `null` sin tickets resueltos en el periodo.
  final double? mttrMedianHours;

  /// n detrás del MTTR: tickets resueltos en el periodo.
  final int sampleSize;
  final bool lowSample;

  /// `null` cuando ningún ticket resuelto tenía SLA.
  final double? slaCompliancePct;
  final int slaSampleSize;
  final bool slaLowSample;
  final int slaExcludedNoSla;

  /// Tickets que pasaron de resuelto a en curso.
  final int reopened;

  @override
  List<Object?> get props => [technicianId, openTickets, resolved, mttrMedianHours, sampleSize, lowSample, slaCompliancePct, slaSampleSize, slaLowSample, slaExcludedNoSla, reopened];
}

/// Indicadores de todos los técnicos visibles en [period] (`7d`, `30d`, `12m`).
class PerformanceReport extends Equatable {
  const PerformanceReport({required this.period, required this.byTechnician});

  factory PerformanceReport.fromJson(Map<String, Object?> json) {
    final rows = json['technicians'];
    return PerformanceReport(
      period: json['period'] as String? ?? '30d',
      byTechnician: {
        if (rows is List)
          for (final row in rows.whereType<Map>()) row['technician_id'] as int: TechnicianPerformance.fromJson(row.cast<String, Object?>()),
      },
    );
  }

  final String period;
  final Map<int, TechnicianPerformance> byTechnician;

  @override
  List<Object?> get props => [period, byTechnician];
}
