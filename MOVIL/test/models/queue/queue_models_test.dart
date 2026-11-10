import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/models/queue/queue_filters.dart';
import 'package:mantix/models/queue/queue_models.dart';
import 'package:mantix/models/queue/queue_workflow.dart';
import 'package:mantix/models/requests/request_models.dart';

import '../../support/requests_support.dart';

const summaryJson = <String, Object?>{
  'generated_at': '2026-11-09T12:00:00Z',
  'period': '30d',
  'pending_total': 14,
  'unassigned': 9,
  'oldest_wait_hours': 245.0,
  'median_wait_hours': 24.1,
  'by_priority': [
    {'key': 'critical', 'count': 2},
    {'key': 'low', 'count': 12},
  ],
  'by_category': [
    {'key': 'network', 'count': 4},
    {'key': 'uncategorized', 'count': 10},
  ],
  'triage_time': {'value': 6.5, 'previous': 5.0, 'change_pct': 30, 'sample_size': 8, 'low_sample': false, 'median_hours': 4.2},
  'decisions': {'approved': 6, 'rejected': 2, 'sample_size': 8, 'low_sample': false, 'approval_rate_pct': 75, 'rejection_rate_pct': 25, 'previous_approval_rate_pct': 80.0, 'change_pct': -6.25},
};

void main() {
  test('QueueSummary lee todo lo que muestran las tarjetas y el pulso', () {
    final summary = QueueSummary.fromJson(summaryJson);

    expect((summary.pendingTotal, summary.unassigned), (14, 9));
    expect((summary.oldestWaitHours, summary.medianWaitHours), (245.0, 24.1));
    expect([for (final c in summary.byPriority) (c.key, c.count)], [('critical', 2), ('low', 12)]);
    expect([for (final c in summary.byCategory) (c.key, c.count)], [('network', 4), ('uncategorized', 10)]);
    expect((summary.triageTime.meanHours, summary.triageTime.medianHours, summary.triageTime.changePct, summary.triageTime.sampleSize), (6.5, 4.2, 30.0, 8));
    expect((summary.decisions.approved, summary.decisions.rejected, summary.decisions.approvalRatePct, summary.decisions.rejectionRatePct, summary.decisions.changePct), (6, 2, 75.0, 25.0, -6.25));
  });

  test('una cola vacía llega con nulos, no con ceros inventados', () {
    final summary = QueueSummary.fromJson({
      'pending_total': 0,
      'unassigned': 0,
      'oldest_wait_hours': null,
      'median_wait_hours': null,
      'by_priority': <Object?>[],
      'by_category': <Object?>[],
      'triage_time': {'value': null, 'previous': null, 'change_pct': null, 'sample_size': 0, 'low_sample': false, 'median_hours': null},
      'decisions': {'approved': 0, 'rejected': 0, 'sample_size': 0, 'low_sample': false, 'approval_rate_pct': null, 'rejection_rate_pct': null, 'previous_approval_rate_pct': null, 'change_pct': null},
    });

    expect(summary.oldestWaitHours, isNull);
    expect(summary.medianWaitHours, isNull);
    expect(summary.triageTime.meanHours, isNull);
    expect(summary.decisions.approvalRatePct, isNull);
    expect(summary.byPriority, isEmpty);
  });

  test('«pocos datos» se lee del servidor', () {
    final summary = QueueSummary.fromJson({
      ...summaryJson,
      'triage_time': {'value': 2.0, 'sample_size': 3, 'low_sample': true},
      'decisions': {'approved': 1, 'rejected': 1, 'sample_size': 2, 'low_sample': true},
    });
    expect(summary.triageTime.lowSample, isTrue);
    expect(summary.decisions.lowSample, isTrue);
    expect(summary.decisions.approvalRatePct, isNull);
  });

  test('un cuerpo incompleto no rompe la lectura', () {
    final summary = QueueSummary.fromJson(const {});
    expect(summary.pendingTotal, 0);
    expect(summary.triageTime.meanHours, isNull);
  });

  group('QueueFilters', () {
    test('cuenta cada filtro de la hoja una sola vez y no la búsqueda', () {
      expect(const QueueFilters(search: 'laptop').activeCount, 0);
      expect(const QueueFilters(categories: ['a', 'b']).activeCount, 1);
      expect(QueueFilters(categories: const ['a'], priorities: const ['high'], technicianIds: const [3], dateFrom: DateTime(2026, 11, 1)).activeCount, 4);
      expect(const QueueFilters().isEmpty, isTrue);
      expect(const QueueFilters(search: ' x ').isEmpty, isFalse);
    });
    test('cleared quita los filtros y conserva la búsqueda', () {
      final cleared = QueueFilters(search: 'red', categories: const ['a'], dateTo: DateTime(2026, 11, 1)).cleared();
      expect(cleared, const QueueFilters(search: 'red'));
    });
  });

  group('QueueWorkflow', () {
    final workflow = QueueWorkflow([
      for (final json in const [
        {'status': 'assigned', 'order': 3, 'allowed_targets': ['in_progress', 'cancelled'], 'requires': ['technician'], 'can_enter': true, 'in_queue': true},
        {'status': 'submitted', 'order': 1, 'allowed_targets': ['triaged', 'assigned', 'cancelled'], 'requires': [], 'can_enter': true, 'in_queue': true},
        {'status': 'triaged', 'order': 2, 'allowed_targets': ['assigned', 'cancelled'], 'requires': ['category', 'priority'], 'can_enter': false, 'in_queue': true},
        {'status': 'in_progress', 'order': 4, 'allowed_targets': [], 'requires': [], 'can_enter': true, 'in_queue': false},
        {'status': 'cancelled', 'order': 9, 'allowed_targets': [], 'requires': ['reason'], 'can_enter': true, 'in_queue': false},
      ])
        WorkflowStatus.fromJson(json),
    ]);
    TicketListItem ticket(String status, {bool canAct = true}) => TicketListItem.fromJson(ticketJson(status: status, canAct: canAct));

    test('las columnas son los estados in_queue, en el orden del servidor', () {
      expect([for (final c in workflow.columns) c.status], ['submitted', 'triaged', 'assigned']);
      expect(workflow.isColumn('cancelled'), isFalse);
    });
    test('canMove exige transición, permiso de entrada y poder actuar', () {
      expect(workflow.canMove(ticket('submitted'), 'assigned'), isTrue);
      expect(workflow.canMove(ticket('submitted'), 'triaged'), isFalse, reason: 'no puede entrar en «Clasificadas»');
      expect(workflow.canMove(ticket('assigned'), 'submitted'), isFalse, reason: 'transición que el flujo no permite');
      expect(workflow.canMove(ticket('submitted', canAct: false), 'assigned'), isFalse);
      expect(workflow.canMove(ticket('submitted'), 'submitted'), isFalse);
      expect(workflow.targetsFor(ticket('submitted')), ['assigned', 'cancelled']);
    });
    test('permissionBlock dice por qué, solo si es por permiso', () {
      String label(String s) => s == 'triaged' ? 'Clasificadas' : s;
      expect(workflow.permissionBlock(ticket('submitted'), 'triaged', label: label), 'Tu rol no puede pasar solicitudes a «Clasificadas».');
      expect(workflow.permissionBlock(ticket('submitted', canAct: false), 'assigned', label: label), isNotNull);
      expect(workflow.permissionBlock(ticket('submitted'), 'assigned', label: label), isNull);
    });
    test('requiresFor sale del servidor', () {
      expect(workflow.requiresFor('triaged'), ['category', 'priority']);
      expect(workflow.requiresFor('assigned'), ['technician']);
      expect(workflow.requiresFor('nope'), isEmpty);
    });
  });
}
