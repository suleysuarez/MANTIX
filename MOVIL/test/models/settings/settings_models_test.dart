import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/models/settings/settings_models.dart';

void main() {
  test('decodes system health and the administrative summary', () {
    final health = SystemHealth.fromJson({
      'generated_at': '2026-11-12T12:00:00Z',
      'overall': 'warning',
      'environment': {
        'name': 'production', 'version': '0.2.0', 'max_upload_mb': 15,
        'reminder_interval_minutes': 60, 'scheduler_enabled': true,
      },
      'users': {'total': 12, 'active': 10, 'inactive': 2, 'without_role': 1},
      'roles': [{'id': 1, 'name': 'Administrador', 'is_active': true, 'users': 1, 'permissions': 48}],
      'audit': {'last_24h': 7, 'recent': [{'id': 9, 'action': 'organization.updated', 'entity_type': 'organization_settings', 'by': 'Admin', 'at': '2026-11-12T11:00:00Z'}]},
      'jobs': [{'id': 'reminders', 'name': 'Recordatorios', 'running': true, 'last_status': 'ok', 'interval_minutes': 60}],
      'integrations': [{'key': 'database', 'name': 'Base de datos', 'status': 'ok', 'detail': 'Conectada', 'latency_ms': 12.5}],
    });

    expect(health.overall, 'warning');
    expect(health.users.active, 10);
    expect(health.users.withoutRole, 1);
    expect(health.roles.single.permissions, 48);
    expect(health.audit.last24h, 7);
    expect(health.audit.recent.single.action, 'organization.updated');
    expect(health.jobs.single.running, isTrue);
    expect(health.integrations.single.latencyMs, 12.5);
    expect(health.environment.maxUploadMb, 15);
  });

  test('decodes organization, categories and priorities', () {
    final organization = OrganizationSettings.fromJson({'company_name': 'Mantix Labs', 'configured': true});
    final category = CategoryAdmin.fromJson({'id': 2, 'code': 'network', 'name': 'Redes', 'is_active': true, 'usage': 3});
    final priority = PriorityAdmin.fromJson({'id': 4, 'code': 'high', 'name': 'Alta', 'level': 4, 'sla_hours': 12, 'is_active': true});

    expect(organization.companyName, 'Mantix Labs');
    expect(organization.configured, isTrue);
    expect(category.usage, 3);
    expect(category.isActive, isTrue);
    expect(priority.level, 4);
    expect(priority.slaHours, 12);
  });

  test('handles missing optional health collections safely', () {
    final health = SystemHealth.fromJson({
      'environment': {}, 'users': {}, 'audit': {},
    });
    expect(health.users.total, 0);
    expect(health.roles, isEmpty);
    expect(health.jobs, isEmpty);
    expect(health.integrations, isEmpty);
  });
}
