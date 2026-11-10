import 'package:equatable/equatable.dart';

/// Categoría de solicitud (`GET /maintenance/categories`): se guarda y se envía su `code`.
class RequestCategory extends Equatable {
  const RequestCategory({required this.code, required this.name});

  factory RequestCategory.fromJson(Map<String, Object?> json) => RequestCategory(code: json['code']! as String, name: json['name']! as String);

  final String code;
  final String name;

  @override
  List<Object?> get props => [code, name];
}

/// Prioridad activa (`GET /priorities`), de la más a la menos urgente según [level].
class PriorityOption extends Equatable {
  const PriorityOption({required this.code, required this.name, required this.level});

  factory PriorityOption.fromJson(Map<String, Object?> json) => PriorityOption(
        code: json['code']! as String,
        name: json['name']! as String,
        level: json['level'] as int? ?? 0,
      );

  final String code;
  final String name;
  final int level;

  @override
  List<Object?> get props => [code, name, level];
}

/// Técnico del catálogo (`GET /technicians`). Solo se ofrecen los activos: [isActive] es el
/// estado de la cuenta del usuario y [isAvailable] la disponibilidad que el técnico declara.
class TechnicianOption extends Equatable {
  const TechnicianOption({
    required this.id,
    required this.fullName,
    required this.email,
    required this.isActive,
    required this.isAvailable,
    this.specialization,
  });

  factory TechnicianOption.fromJson(Map<String, Object?> json) => TechnicianOption(
        id: json['id']! as int,
        fullName: json['full_name']! as String,
        email: (json['email'] as String?) ?? '',
        specialization: json['specialization'] as String?,
        isActive: json['is_active'] as bool? ?? true,
        isAvailable: json['is_available'] as bool? ?? true,
      );

  final int id;
  final String fullName;
  final String email;
  final String? specialization;
  final bool isActive;
  final bool isAvailable;

  @override
  List<Object?> get props => [id, fullName, email, specialization, isActive, isAvailable];
}
