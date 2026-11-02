import { Technician, TechnicianWorkload } from '../../core/technicians.service';
import {
  EMPTY_TECHNICIAN_FILTERS, TechnicianFilters, allSpecialties, filterTechnicians, hasTechnicianFilters, specialties, summarize,
  technicianStatus, validateTechnicianInput,
} from './technician-ui';

const tech = (id: number, name: string, overrides: Partial<Technician> = {}): Technician => ({
  id, user_id: id + 100, full_name: name, email: `${name.split(' ')[0].toLowerCase()}@mantix.io`,
  employee_code: null, specialization: null, is_available: true, is_active: true, hourly_rate: null,
  created_at: '2026-01-01T00:00:00Z', ...overrides,
});
const load = (id: number, open: number, resolved: number): TechnicianWorkload =>
  ({ technician_id: id, full_name: '', is_available: true, open_tickets: open, resolved_in_window: resolved });

const carlos = tech(1, 'Carlos Rivera', { specialization: 'Hardware, Soldadura SMD' });
const laura = tech(2, 'Laura Peña', { specialization: 'Redes', employee_code: 'EMP-7' });
const sofia = tech(3, 'Sofía Navarro', { specialization: 'hardware', is_available: false });
const loads = { 1: load(1, 2, 40), 2: load(2, 0, 51), 3: load(3, 0, 10) };
const all = [carlos, laura, sofia];
const filters = (changes: Partial<TechnicianFilters>): TechnicianFilters => ({ ...EMPTY_TECHNICIAN_FILTERS, ...changes });
const ids = (list: Technician[]) => list.map((t) => t.id);

describe('technician-ui', () => {
  it('derives the operational status from availability and open tickets', () => {
    expect(technicianStatus(carlos, loads)).toBe('busy');
    expect(technicianStatus(laura, loads)).toBe('free');
    expect(technicianStatus(sofia, loads)).toBe('unavailable');
    expect(technicianStatus(laura, {})).toBe('free');
  });

  it('splits the free-text specialization into tags', () => {
    expect(specialties(carlos)).toEqual(['Hardware', 'Soldadura SMD']);
    expect(specialties(tech(9, 'Sin Area'))).toEqual([]);
  });

  it('lists each specialty once, ignoring case', () => {
    expect(allSpecialties(all)).toEqual(['Hardware', 'Redes', 'Soldadura SMD']);
  });

  it('searches by name, e-mail, code or specialty without caring about accents', () => {
    expect(ids(filterTechnicians(all, loads, filters({ search: 'sofia' })))).toEqual([3]);
    expect(ids(filterTechnicians(all, loads, filters({ search: 'emp-7' })))).toEqual([2]);
    expect(ids(filterTechnicians(all, loads, filters({ search: 'laura@' })))).toEqual([2]);
    expect(ids(filterTechnicians(all, loads, filters({ search: 'smd' })))).toEqual([1]);
  });

  it('filters by status and by specialty', () => {
    expect(ids(filterTechnicians(all, loads, filters({ status: 'busy' })))).toEqual([1]);
    expect(ids(filterTechnicians(all, loads, filters({ specialty: 'Hardware' })))).toEqual([1, 3]);
  });

  it('filters by account state, availability and load', () => {
    const inactive = tech(4, 'Inés Mora', { is_active: false });
    const team = [...all, inactive];
    expect(ids(filterTechnicians(team, loads, filters({ active: 'inactive' })))).toEqual([4]);
    expect(ids(filterTechnicians(team, loads, filters({ active: 'active' }))).sort()).toEqual([1, 2, 3]);
    expect(ids(filterTechnicians(team, loads, filters({ availability: 'unavailable' })))).toEqual([3]);
    expect(ids(filterTechnicians(team, loads, filters({ load: 'low' })))).toEqual([1]); // 2 open tickets
    expect(ids(filterTechnicians(team, loads, filters({ load: 'none' }))).sort()).toEqual([2, 3, 4]);
    expect(ids(filterTechnicians(team, { ...loads, 2: load(2, 5, 0) }, filters({ load: 'high' })))).toEqual([2]);
    expect(ids(filterTechnicians(team, loads, filters({ availability: 'available', load: 'none', active: 'active' })))).toEqual([2]);
  });

  it('knows whether any filter is applied', () => {
    expect(hasTechnicianFilters(EMPTY_TECHNICIAN_FILTERS)).toBeFalse();
    expect(hasTechnicianFilters(filters({ load: 'high' }))).toBeTrue();
    expect(hasTechnicianFilters(filters({ order: 'name' }))).toBeFalse();
  });

  it('orders by availability, load and resolved tickets', () => {
    expect(ids(filterTechnicians(all, loads, filters({})))).toEqual([2, 1, 3]);
    expect(ids(filterTechnicians(all, loads, filters({ order: 'load' })))).toEqual([2, 3, 1]);
    expect(ids(filterTechnicians(all, loads, filters({ order: 'resolved' })))).toEqual([2, 1, 3]);
    expect(ids(filterTechnicians(all, loads, filters({ order: 'name' })))).toEqual([1, 2, 3]);
  });

  it('summarizes the team', () => {
    expect(summarize(all, loads)).toEqual({
      total: 3, available: 2, busy: 1, unavailable: 1, openTickets: 2, resolved: 101,
    });
  });

  it('validates the technician form', () => {
    expect(validateTechnicianInput({ userId: null, specialization: '', rate: '' }, true)).toContain('Selecciona');
    expect(validateTechnicianInput({ userId: null, specialization: '', rate: '' }, false)).toBe('');
    expect(validateTechnicianInput({ userId: 1, specialization: 'x'.repeat(101), rate: '' }, true)).toContain('100');
    expect(validateTechnicianInput({ userId: 1, specialization: '', rate: '-1' }, true)).toContain('mayor a cero');
    expect(validateTechnicianInput({ userId: 1, specialization: '', rate: '1.234' }, true)).toContain('dos decimales');
    expect(validateTechnicianInput({ userId: 1, specialization: '', rate: '1e12' }, true)).toContain('máximo');
    expect(validateTechnicianInput({ userId: 1, specialization: 'Redes', rate: '25.50' }, true)).toBe('');
  });
});
