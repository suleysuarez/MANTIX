import { MaintenanceSchedule } from '../../core/schedules.service';
import { csvCell, planStatus, plansToCsv } from './plan-csv';

const plan = (overrides: Partial<MaintenanceSchedule> = {}): MaintenanceSchedule => ({
  id: 1, equipment: { id: 1, asset_tag: 'LT-1', brand: 'Dell', model: 'X' }, technician: null, title: 'Limpieza',
  description: null, interval_days: 30, estimated_hours: '1.50', remind_days_before: 3,
  next_due_at: '2026-12-01T09:00:00Z', last_reminded_at: null, is_active: true, created_at: '2026-10-01T00:00:00Z',
  ...overrides,
});

describe('plan CSV', () => {
  it('quotes commas, quotes and line breaks', () => {
    expect(csvCell('a,b')).toBe('"a,b"');
    expect(csvCell('di "hola"')).toBe('"di ""hola"""');
    expect(csvCell('uno\ndos')).toBe('"uno\ndos"');
    expect(csvCell(null)).toBe('');
  });

  it('neutralises spreadsheet formulas', () => {
    for (const evil of ['=1+1', '+SUM(A1)', '-2', '@cmd', '\t=x']) {
      expect(csvCell(evil).startsWith("'") || csvCell(evil).startsWith('"\'')).toBeTrue();
    }
    expect(csvCell('normal')).toBe('normal');
  });

  it('classifies a plan as inactive, overdue or scheduled', () => {
    const now = new Date('2026-10-14T12:00:00Z');
    expect(planStatus(plan({ is_active: false }), now)).toBe('Inactivo');
    expect(planStatus(plan({ next_due_at: '2026-10-01T00:00:00Z' }), now)).toBe('Vencido');
    expect(planStatus(plan(), now)).toBe('Programado');
  });

  it('writes a header and one row per plan', () => {
    const csv = plansToCsv([plan({ title: '=HYPERLINK("x")' }), plan({ technician: { id: 2, user_id: 2, full_name: 'Luis' } })]);
    const lines = csv.split('\r\n');
    expect(lines[0]).toBe('Plan,Equipo,Técnico,Intervalo (días),Horas estimadas,Próximo servicio,Estado');
    expect(lines.length).toBe(3);
    expect(lines[1].startsWith('"\'=HYPERLINK')).toBeTrue();
    expect(lines[2]).toContain('Luis');
  });
});
