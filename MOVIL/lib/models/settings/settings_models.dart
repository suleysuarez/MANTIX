import 'package:equatable/equatable.dart';

int _int(Object? value, [int fallback = 0]) => value is num ? value.toInt() : int.tryParse('$value') ?? fallback;
double? _double(Object? value) => value is num ? value.toDouble() : double.tryParse('$value');

class SystemHealth extends Equatable {
  const SystemHealth({required this.generatedAt, required this.overall, required this.environment, required this.users, required this.roles, required this.audit, required this.jobs, required this.integrations});
  final DateTime generatedAt;
  final String overall;
  final EnvironmentInfo environment;
  final UserCounts users;
  final List<RoleHealth> roles;
  final AuditHealth audit;
  final List<JobHealth> jobs;
  final List<IntegrationHealth> integrations;
  factory SystemHealth.fromJson(Map<String, Object?> json) {
    final env = (json['environment'] as Map? ?? const {}).cast<String, Object?>();
    final users = (json['users'] as Map? ?? const {}).cast<String, Object?>();
    final audit = (json['audit'] as Map? ?? const {}).cast<String, Object?>();
    List<T> parse<T>(Object? value, T Function(Map<String, Object?>) parser) => [
      if (value is List) for (final item in value) if (item is Map) parser(item.cast<String, Object?>()),
    ];
    return SystemHealth(
      generatedAt: DateTime.tryParse('${json['generated_at'] ?? ''}') ?? DateTime.now(),
      overall: json['overall'] as String? ?? 'warning',
      environment: EnvironmentInfo.fromJson(env), users: UserCounts.fromJson(users),
      roles: parse(json['roles'], RoleHealth.fromJson), audit: AuditHealth.fromJson(audit),
      jobs: parse(json['jobs'], JobHealth.fromJson), integrations: parse(json['integrations'], IntegrationHealth.fromJson),
    );
  }
  @override
  List<Object?> get props => [generatedAt, overall, environment, users, roles, audit, jobs, integrations];
}

class EnvironmentInfo extends Equatable {
  const EnvironmentInfo({required this.name, required this.version, required this.maxUploadMb, required this.reminderIntervalMinutes, required this.schedulerEnabled});
  final String name, version;
  final int maxUploadMb, reminderIntervalMinutes;
  final bool schedulerEnabled;
  factory EnvironmentInfo.fromJson(Map<String, Object?> json) => EnvironmentInfo(
    name: json['name'] as String? ?? '—', version: json['version'] as String? ?? '—',
    maxUploadMb: _int(json['max_upload_mb']), reminderIntervalMinutes: _int(json['reminder_interval_minutes']),
    schedulerEnabled: json['scheduler_enabled'] as bool? ?? false,
  );
  @override
  List<Object?> get props => [name, version, maxUploadMb, reminderIntervalMinutes, schedulerEnabled];
}

class UserCounts extends Equatable {
  const UserCounts({required this.total, required this.active, required this.inactive, required this.withoutRole});
  final int total, active, inactive, withoutRole;
  factory UserCounts.fromJson(Map<String, Object?> json) => UserCounts(total: _int(json['total']), active: _int(json['active']), inactive: _int(json['inactive']), withoutRole: _int(json['without_role']));
  @override
  List<Object?> get props => [total, active, inactive, withoutRole];
}

class RoleHealth extends Equatable {
  const RoleHealth({required this.id, required this.name, required this.isActive, required this.users, required this.permissions});
  final int id, users, permissions;
  final String name;
  final bool isActive;
  factory RoleHealth.fromJson(Map<String, Object?> json) => RoleHealth(id: _int(json['id']), name: json['name'] as String? ?? '', isActive: json['is_active'] as bool? ?? true, users: _int(json['users']), permissions: _int(json['permissions']));
  @override
  List<Object?> get props => [id, name, isActive, users, permissions];
}

class AuditHealth extends Equatable {
  const AuditHealth({required this.last24h, required this.recent});
  final int last24h;
  final List<AuditEntry> recent;
  factory AuditHealth.fromJson(Map<String, Object?> json) => AuditHealth(
    last24h: _int(json['last_24h']),
    recent: [if (json['recent'] is List) for (final item in json['recent'] as List) if (item is Map) AuditEntry.fromJson(item.cast<String, Object?>())],
  );
  @override
  List<Object?> get props => [last24h, recent];
}

class AuditEntry extends Equatable {
  const AuditEntry({required this.id, required this.action, required this.entityType, required this.by, required this.at});
  final int id;
  final String action, entityType;
  final String? by;
  final DateTime? at;
  factory AuditEntry.fromJson(Map<String, Object?> json) => AuditEntry(
    id: _int(json['id']), action: json['action'] as String? ?? '', entityType: json['entity_type'] as String? ?? '',
    by: json['by'] as String?, at: DateTime.tryParse('${json['at'] ?? ''}'),
  );
  @override
  List<Object?> get props => [id, action, entityType, by, at];
}

class JobHealth extends Equatable {
  const JobHealth({required this.id, required this.name, required this.running, required this.lastStatus, this.intervalMinutes, this.nextRunAt, this.lastRunAt, this.lastDetail});
  final String id, name, lastStatus;
  final bool running;
  final int? intervalMinutes;
  final DateTime? nextRunAt, lastRunAt;
  final String? lastDetail;
  factory JobHealth.fromJson(Map<String, Object?> json) => JobHealth(
    id: json['id'] as String? ?? '', name: json['name'] as String? ?? '', running: json['running'] as bool? ?? false,
    lastStatus: json['last_status'] as String? ?? 'never', intervalMinutes: json['interval_minutes'] == null ? null : _int(json['interval_minutes']),
    nextRunAt: DateTime.tryParse('${json['next_run_at'] ?? ''}'), lastRunAt: DateTime.tryParse('${json['last_run_at'] ?? ''}'), lastDetail: json['last_detail'] as String?,
  );
  @override
  List<Object?> get props => [id, name, running, lastStatus, intervalMinutes, nextRunAt, lastRunAt, lastDetail];
}

class IntegrationHealth extends Equatable {
  const IntegrationHealth({required this.key, required this.name, required this.status, required this.detail, this.latencyMs});
  final String key, name, status, detail;
  final double? latencyMs;
  factory IntegrationHealth.fromJson(Map<String, Object?> json) => IntegrationHealth(
    key: json['key'] as String? ?? '', name: json['name'] as String? ?? '', status: json['status'] as String? ?? 'warning',
    detail: json['detail'] as String? ?? '', latencyMs: _double(json['latency_ms']),
  );
  @override
  List<Object?> get props => [key, name, status, detail, latencyMs];
}

class CategoryAdmin extends Equatable {
  const CategoryAdmin({required this.id, required this.code, required this.name, required this.isActive, required this.usage, this.createdAt});
  final int id, usage;
  final String code, name;
  final bool isActive;
  final DateTime? createdAt;
  factory CategoryAdmin.fromJson(Map<String, Object?> json) => CategoryAdmin(
    id: _int(json['id']), code: json['code'] as String? ?? '', name: json['name'] as String? ?? '',
    isActive: json['is_active'] as bool? ?? true, usage: _int(json['usage']), createdAt: DateTime.tryParse('${json['created_at'] ?? ''}'),
  );
  @override
  List<Object?> get props => [id, code, name, isActive, usage, createdAt];
}

class PriorityAdmin extends Equatable {
  const PriorityAdmin({required this.id, required this.code, required this.name, required this.level, required this.isActive, this.description, this.slaHours});
  final int id, level;
  final String code, name;
  final bool isActive;
  final String? description;
  final int? slaHours;
  factory PriorityAdmin.fromJson(Map<String, Object?> json) => PriorityAdmin(
    id: _int(json['id']), code: json['code'] as String? ?? '', name: json['name'] as String? ?? '',
    level: _int(json['level']), isActive: json['is_active'] as bool? ?? true,
    description: json['description'] as String?, slaHours: json['sla_hours'] == null ? null : _int(json['sla_hours']),
  );
  @override
  List<Object?> get props => [id, code, name, level, isActive, description, slaHours];
}

class OrganizationSettings extends Equatable {
  const OrganizationSettings({required this.companyName, required this.configured, this.updatedAt});
  final String companyName;
  final bool configured;
  final DateTime? updatedAt;
  factory OrganizationSettings.fromJson(Map<String, Object?> json) => OrganizationSettings(
    companyName: json['company_name'] as String? ?? 'Mantix', configured: json['configured'] as bool? ?? false,
    updatedAt: DateTime.tryParse('${json['updated_at'] ?? ''}'),
  );
  @override
  List<Object?> get props => [companyName, configured, updatedAt];
}
