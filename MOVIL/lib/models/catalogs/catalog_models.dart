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
