/// Modelos de la bandeja de triaje (`GET /maintenance/queue/summary`). Escritos a mano; un
/// número ausente es `null`, nunca cero inventado.
library;

import 'package:equatable/equatable.dart';

double? _double(Object? value) => value is num ? value.toDouble() : null;

int _int(Object? value) => value is num ? value.toInt() : 0;

/// Una barra de «Por prioridad» o «Por categoría»: el código y cuántas solicitudes hay.
class QueueCount extends Equatable {
  const QueueCount({required this.key, required this.count});

  factory QueueCount.fromJson(Map<String, Object?> json) => QueueCount(key: json['key']! as String, count: _int(json['count']));

  /// Código de prioridad o de categoría (`uncategorized` si no tiene).
  final String key;
  final int count;

  @override
  List<Object?> get props => [key, count];
}

/// Primera respuesta: cuánto tarda una solicitud en clasificarse o resolverse su triaje.
class TriageTime extends Equatable {
  const TriageTime({this.meanHours, this.medianHours, this.previousHours, this.changePct, this.sampleSize = 0, this.lowSample = false});

  factory TriageTime.fromJson(Map<String, Object?> json) => TriageTime(
        meanHours: _double(json['value']),
        medianHours: _double(json['median_hours']),
        previousHours: _double(json['previous']),
        changePct: _double(json['change_pct']),
        sampleSize: _int(json['sample_size']),
        lowSample: json['low_sample'] as bool? ?? false,
      );

  /// Media en horas; `null` si no hubo decisiones en el periodo.
  final double? meanHours;
  final double? medianHours;
  final double? previousHours;

  /// Variación contra el periodo anterior; `null` si no hay base de comparación.
  final double? changePct;
  final int sampleSize;

  /// Pocas decisiones (menos de 5): el dato es orientativo.
  final bool lowSample;

  @override
  List<Object?> get props => [meanHours, medianHours, previousHours, changePct, sampleSize, lowSample];
}

/// Aprobadas y rechazadas en el periodo.
class QueueDecisions extends Equatable {
  const QueueDecisions({this.approved = 0, this.rejected = 0, this.sampleSize = 0, this.lowSample = false, this.approvalRatePct, this.rejectionRatePct, this.previousApprovalRatePct, this.changePct});

  factory QueueDecisions.fromJson(Map<String, Object?> json) => QueueDecisions(
        approved: _int(json['approved']),
        rejected: _int(json['rejected']),
        sampleSize: _int(json['sample_size']),
        lowSample: json['low_sample'] as bool? ?? false,
        approvalRatePct: _double(json['approval_rate_pct']),
        rejectionRatePct: _double(json['rejection_rate_pct']),
        previousApprovalRatePct: _double(json['previous_approval_rate_pct']),
        changePct: _double(json['change_pct']),
      );

  final int approved;
  final int rejected;
  final int sampleSize;
  final bool lowSample;
  final double? approvalRatePct;
  final double? rejectionRatePct;
  final double? previousApprovalRatePct;
  final double? changePct;

  @override
  List<Object?> get props => [approved, rejected, sampleSize, lowSample, approvalRatePct, rejectionRatePct, previousApprovalRatePct, changePct];
}

/// Resumen de la cola de solicitudes pendientes: todo lo que muestran las tarjetas de arriba y
/// «Pulso de la cola» sale de una sola respuesta.
class QueueSummary extends Equatable {
  const QueueSummary({
    required this.pendingTotal,
    required this.unassigned,
    required this.byPriority,
    required this.byCategory,
    required this.triageTime,
    required this.decisions,
    this.oldestWaitHours,
    this.medianWaitHours,
    this.period,
  });

  factory QueueSummary.fromJson(Map<String, Object?> json) {
    List<QueueCount> counts(Object? raw) => raw is List ? [for (final item in raw) QueueCount.fromJson((item as Map).cast<String, Object?>())] : const [];
    Map<String, Object?> map(Object? raw) => raw is Map ? raw.cast<String, Object?>() : const {};
    return QueueSummary(
      period: json['period'] as String?,
      pendingTotal: _int(json['pending_total']),
      unassigned: _int(json['unassigned']),
      oldestWaitHours: _double(json['oldest_wait_hours']),
      medianWaitHours: _double(json['median_wait_hours']),
      byPriority: counts(json['by_priority']),
      byCategory: counts(json['by_category']),
      triageTime: TriageTime.fromJson(map(json['triage_time'])),
      decisions: QueueDecisions.fromJson(map(json['decisions'])),
    );
  }

  /// Periodo de las decisiones (`7d`, `30d` o `12m`), tal como lo devuelve el servidor.
  final String? period;

  /// Solicitudes en cola (recibidas, clasificadas y asignadas sin iniciar).
  final int pendingTotal;
  final int unassigned;
  final double? oldestWaitHours;

  /// El servidor entrega la mediana de la espera, no la media.
  final double? medianWaitHours;

  /// De la más urgente a la menos.
  final List<QueueCount> byPriority;
  final List<QueueCount> byCategory;
  final TriageTime triageTime;
  final QueueDecisions decisions;

  @override
  List<Object?> get props => [period, pendingTotal, unassigned, oldestWaitHours, medianWaitHours, byPriority, byCategory, triageTime, decisions];
}
