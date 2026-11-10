import 'package:equatable/equatable.dart';

DateTime? _dateOrNull(Object? value) => value is String ? DateTime.tryParse(value)?.toLocal() : null;

/// Un trabajo de mantenimiento registrado sobre un equipo
/// (`GET /equipment/{id}/maintenance-records`). Los costos llegan como texto decimal y vacíos
/// si quien llama no puede verlos.
class MaintenanceRecord extends Equatable {
  const MaintenanceRecord({
    required this.id,
    required this.workType,
    required this.startedAt,
    required this.diagnosis,
    required this.actionsTaken,
    required this.result,
    this.requestId,
    this.completedAt,
    this.laborCost,
    this.partsCost,
    this.totalCost,
    this.notes,
  });

  factory MaintenanceRecord.fromJson(Map<String, Object?> json) => MaintenanceRecord(
        id: json['id']! as int,
        requestId: json['request_id'] as int?,
        workType: (json['work_type'] as String?) ?? 'other',
        startedAt: DateTime.parse(json['started_at']! as String).toLocal(),
        completedAt: _dateOrNull(json['completed_at']),
        diagnosis: (json['diagnosis'] as String?) ?? '',
        actionsTaken: (json['actions_taken'] as String?) ?? '',
        result: (json['result'] as String?) ?? '',
        laborCost: json['labor_cost'] as String?,
        partsCost: json['parts_cost'] as String?,
        totalCost: json['total_cost'] as String?,
        notes: json['notes'] as String?,
      );

  final int id;
  final int? requestId;
  final String workType;
  final DateTime startedAt;
  final DateTime? completedAt;
  final String diagnosis;
  final String actionsTaken;
  final String result;
  final String? laborCost;
  final String? partsCost;
  final String? totalCost;
  final String? notes;

  /// Tipo de trabajo en español; un código nuevo del servidor se muestra tal cual.
  String get workTypeLabel => switch (workType) {
        'corrective' => 'Correctivo',
        'preventive' => 'Preventivo',
        'inspection' => 'Inspección',
        'installation' => 'Instalación',
        'recovery' => 'Recuperación',
        'other' => 'Otro',
        _ => workType,
      };

  /// Resultado con la primera letra en mayúscula (el servidor lo guarda como texto libre).
  String get resultLabel => result.isEmpty ? '' : '${result[0].toUpperCase()}${result.substring(1).replaceAll('_', ' ')}';

  @override
  List<Object?> get props => [id, requestId, workType, startedAt, completedAt, diagnosis, actionsTaken, result, laborCost, partsCost, totalCost, notes];
}
