import { Equipment } from './equipment.service';
import { MaintenanceListItem } from './maintenance.service';
import { buildMetrics, buildSeries } from './dashboard.store';

const NOW = new Date(2026, 9, 1, 12);

function equipment(id: number, status: string, type = 'Laptop'): Equipment {
  return {
    id, asset_tag: `A${id}`, serial_number: null, equipment_type_id: 1,
    equipment_type: { id: 1, code: type, name: type }, brand: 'b', model: 'm',
    description: null, status, purchase_date: null, purchase_cost: null,
    warranty_start_date: null, warranty_end_date: null, created_at: '2026-01-01T00:00:00Z',
    current_location: null, current_custodian: null, last_maintenance: null,
  };
}

function ticket(id: number, status: string, priority: string, created: Date): MaintenanceListItem {
  return {
    id, ticket_number: `T${id}`, equipment_id: 1, title: 't', priority, status,
    created_at: created.toISOString(),
  };
}

describe('buildMetrics', () => {
  it('returns zeros for empty data', () => {
    const metrics = buildMetrics([], [], [], NOW);
    expect(metrics.operationalPct).toBe(0);
    expect(metrics.resolutionPct).toBe(0);
    expect(metrics.week.length).toBe(7);
  });

  it('computes operational share, ticket buckets and the weekly peak', () => {
    const metrics = buildMetrics(
      [equipment(1, 'assigned'), equipment(2, 'in_repair'), equipment(3, 'in_storage', 'Server'), equipment(4, 'retired')],
      [
        ticket(1, 'in_progress', 'critical', NOW),
        ticket(2, 'submitted', 'low', NOW),
        ticket(3, 'resolved', 'high', new Date(2026, 9, 1, 8)),
      ],
      [{ id: 1, user_id: 1, full_name: 'T', email: 't@x.io', employee_code: null, specialization: null, is_available: true, hourly_rate: null, created_at: '2026-01-01T00:00:00Z' }],
      NOW,
    );
    expect(metrics.operationalPct).toBe(50);
    expect(metrics.byType[0]).toEqual({ name: 'Laptop', count: 3 });
    expect(metrics.activeTickets).toBe(1);
    expect(metrics.pendingTickets).toBe(1);
    expect(metrics.urgentTickets).toBe(1);
    expect(metrics.monthTickets).toBe(3);
    expect(metrics.resolutionPct).toBe(33);
    expect(metrics.week[6]).toEqual({ label: 'Jue', count: 3, isPeak: true });
    expect(metrics.techniciansAvailable).toBe(1);
  });
});

describe('buildSeries and extended metrics', () => {
  it('builds 7, 30 and 12 buckets', () => {
    expect(buildSeries([], '7d', NOW).length).toBe(7);
    expect(buildSeries([], '30d', NOW).length).toBe(30);
    expect(buildSeries([], '12m', NOW).length).toBe(12);
  });

  it('groups tickets by month for the 12m period', () => {
    const series = buildSeries([ticket(1, 'submitted', 'low', NOW), ticket(2, 'submitted', 'low', new Date(2026, 7, 5))], '12m', NOW);
    expect(series[11]).toEqual({ label: 'Oct', count: 1, isPeak: true });
    expect(series[9].count).toBe(1);
  });

  it('keeps health categories mutually exclusive and computes the month trend', () => {
    const metrics = buildMetrics(
      [equipment(1, 'assigned'), equipment(2, 'in_repair'), equipment(3, 'lost'), equipment(4, 'weird')],
      [
        ticket(1, 'submitted', 'critical', NOW),
        ticket(2, 'submitted', 'low', NOW),
        ticket(3, 'resolved', 'low', new Date(2026, 8, 10)),
      ],
      [],
      NOW,
    );
    expect(metrics.health).toEqual({ operational: 1, maintenance: 1, offline: 1, other: 1 });
    expect(metrics.monthTrendPct).toBe(100);
    expect(metrics.attention[0].critical).toBeTrue();
    expect(buildMetrics([], [], [], NOW).monthTrendPct).toBeNull();
  });
});
