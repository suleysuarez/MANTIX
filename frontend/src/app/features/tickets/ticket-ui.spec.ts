import { MaintenanceListItem } from '../../core/maintenance.service';
import {
  countByStatus, initials, isActive, isUnassigned, needingAttention, priorityMeta, statusMeta, ticketsToCsv,
} from './ticket-ui';

const row = (id: number, status: string, priority: string, title = 't'): MaintenanceListItem => ({
  id, ticket_number: `TCK-${id}`, equipment_id: 1, title, priority, status, created_at: '2026-01-01T00:00:00Z',
});

describe('ticket-ui', () => {
  it('labels known statuses and falls back to the raw code', () => {
    expect(statusMeta('in_progress').label).toBe('En proceso');
    expect(statusMeta('mystery').label).toBe('mystery');
    expect(priorityMeta('critical').label).toBe('Crítica');
  });

  it('counts tickets per status', () => {
    expect(countByStatus([row(1, 'closed', 'low'), row(2, 'closed', 'low'), row(3, 'waiting', 'low')]))
      .toEqual({ closed: 2, waiting: 1 });
  });

  it('flags only active critical/high tickets, most urgent first', () => {
    const result = needingAttention([
      row(1, 'in_progress', 'high'),
      row(2, 'submitted', 'critical'),
      row(3, 'closed', 'critical'),
      row(4, 'submitted', 'medium'),
    ]);

    expect(result.map((item) => item.id)).toEqual([2, 1]);
  });

  it('knows which statuses are unassigned and which are still active', () => {
    expect(isUnassigned('triaged')).toBeTrue();
    expect(isUnassigned('assigned')).toBeFalse();
    expect(isActive('waiting')).toBeTrue();
    expect(isActive('cancelled')).toBeFalse();
  });

  it('builds initials from the first two words', () => {
    expect(initials('Carlos Andrés Rivera')).toBe('CA');
  });

  it('escapes CSV cells that contain commas or quotes', () => {
    const csv = ticketsToCsv([row(1, 'submitted', 'high', 'Pantalla, "negra"')], () => 'EQ-1');

    expect(csv.split('\r\n')[1]).toContain('"Pantalla, ""negra"""');
    expect(csv.split('\r\n')[0]).toBe('Ticket,Título,Equipo,Prioridad,Estado,Creado');
  });
});
