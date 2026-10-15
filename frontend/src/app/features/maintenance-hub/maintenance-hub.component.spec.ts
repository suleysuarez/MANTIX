import { Component } from '@angular/core';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { BehaviorSubject, of } from 'rxjs';

import { addDays, dayKey, startOfDay, toLocalInput } from '../../core/calendar-utils';
import { Equipment } from '../../core/equipment.service';
import { LocalProfileService } from '../../core/local-profile.service';
import { EMPTY_LIST_FILTERS, MaintenanceHubState, MaintenanceHubStore } from '../../core/maintenance-hub.store';
import { CalendarEvent, MaintenanceOverview } from '../../core/maintenance-overview.service';
import { MaintenanceSchedule } from '../../core/schedules.service';
import { Technician } from '../../core/technicians.service';
import { WCAG_AA, contrastRatio, flatten } from '../dashboard/contrast';
import { MaintenanceHubComponent } from './maintenance-hub.component';

const TODAY = startOfDay(new Date());
const atNoon = (date: Date) => new Date(date.getFullYear(), date.getMonth(), date.getDate(), 12).toISOString();

const event = (kind: CalendarEvent['kind'], date: Date, extra: Partial<CalendarEvent> = {}): CalendarEvent => ({
  kind, schedule_id: 1, title: 'Limpieza', equipment_id: 1, asset_tag: 'LT-1', technician: 'Luis', at: atNoon(date),
  completed_at: null, on_time: null, ...extra,
});

const plan = (overrides: Partial<MaintenanceSchedule> = {}): MaintenanceSchedule => ({
  id: 1, equipment: { id: 1, asset_tag: 'LT-1', brand: 'Dell', model: 'X' }, technician: null, title: 'Limpieza interna',
  description: null, interval_days: 30, estimated_hours: '1.50', remind_days_before: 3,
  next_due_at: addDays(TODAY, 5).toISOString(), last_reminded_at: null, is_active: true, created_at: '2026-10-01T00:00:00Z',
  ...overrides,
});

const overview = {
  period: '30d',
  mix: { preventive: 6, corrective: 4, other: 0, sample_size: 10, low_sample: false, preventive_pct: 60, previous_preventive_pct: 20, change_pct: 200 },
  upcoming: { overdue: 2, next_7_days: 4, next_30_days: 9 },
  compliance: { weeks: [], planned: 3, on_time: 2, sample_size: 3, low_sample: true, compliance_pct: 66.7, previous_compliance_pct: null, change_pct: null },
  duration: { average_actual_hours: 3, average_estimated_hours: 2, variance_pct: 50, previous_variance_pct: null, sample_size: 7, low_sample: false },
  cost: { total: '300.50', previous_total: '200.00', change_pct: 50.3, records_with_cost: 3, average_per_record: '100.17', low_sample: true },
  reschedules: { count: 1, previous: 0, change_pct: null },
} as unknown as MaintenanceOverview;

function state(overrides: Partial<MaintenanceHubState> = {}): MaintenanceHubState {
  return {
    view: 'calendar', mode: 'month', anchor: TODAY, selectedDay: null, period: '30d', overview, overviewLoading: false,
    events: [event('planned', TODAY), event('overdue', TODAY, { schedule_id: 2, title: 'Firmware' })],
    truncated: false, calendarLoading: false, calendarError: '',
    timeline: [event('overdue', addDays(TODAY, -2), { schedule_id: 2 }), event('planned', addDays(TODAY, 1), { schedule_id: 3 })],
    list: [], listTotal: 0, listPage: 1, listLoading: false, listError: '', filters: EMPTY_LIST_FILTERS,
    technicians: [{ id: 2, user_id: 2, full_name: 'Luis', is_available: true } as Technician],
    equipment: [
      { id: 1, asset_tag: 'LT-1', brand: 'Dell', model: 'X', status: 'assigned' } as Equipment,
      { id: 2, asset_tag: 'LT-9', brand: 'HP', model: 'Y', status: 'retired' } as Equipment,
    ],
    selectedId: null, plan: null, history: null, detailLoading: false, detailError: '', busy: false, ...overrides,
  };
}

@Component({
  standalone: true,
  imports: [MaintenanceHubComponent],
  template: '<div class="tw-reset"><app-maintenance-hub /></div>',
})
class ShellHostComponent {}

describe('MaintenanceHubComponent', () => {
  let subject: BehaviorSubject<MaintenanceHubState>;
  let store: jasmine.SpyObj<MaintenanceHubStore>;
  let fixture: ComponentFixture<ShellHostComponent>;
  let canManage: boolean;

  const host = () => fixture.nativeElement as HTMLElement;
  const render = (value: MaintenanceHubState) => {
    subject.next(value);
    fixture.detectChanges();
  };
  const click = (el: Element | null) => {
    (el as HTMLElement).click();
    fixture.detectChanges();
  };
  const button = (text: string) => Array.from(host().querySelectorAll('button')).find((b) => b.textContent?.includes(text)) ?? null;
  const type = (selector: string, value: string) => {
    const input = host().querySelector(selector) as HTMLInputElement | HTMLTextAreaElement;
    input.value = value;
    input.dispatchEvent(new Event('input'));
    input.dispatchEvent(new Event('blur'));
    fixture.detectChanges();
  };

  async function create(manage = true) {
    canManage = manage;
    subject = new BehaviorSubject(state());
    store = Object.assign(
      jasmine.createSpyObj('MaintenanceHubStore', ['load', 'setView', 'setMode', 'navigate', 'goToday', 'selectDay', 'setPeriod', 'setFilters', 'clearFilters', 'setListPage', 'selectPlan', 'create', 'update', 'complete', 'exportAll']),
      { state$: subject },
    );
    for (const method of ['create', 'update', 'complete'] as const) {
      (store[method] as jasmine.Spy).and.returnValue(of({ ok: true, fieldErrors: {} }));
    }
    TestBed.configureTestingModule({
      providers: [
        provideRouter([]),
        { provide: MaintenanceHubStore, useValue: store },
        { provide: LocalProfileService, useValue: { can: () => Promise.resolve(canManage), getProfile: () => Promise.resolve({ full_name: '' }) } },
      ],
    });
    fixture = TestBed.createComponent(ShellHostComponent);
    document.body.appendChild(host());
    fixture.detectChanges();
    await fixture.whenStable();
    fixture.detectChanges();
  }

  afterEach(() => host().remove());

  describe('calendar', () => {
    beforeEach(() => create());

    it('shows the month with its events on the right day, colour-coded by kind', () => {
      const todayCell = host().querySelector(`[aria-label^="${['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb'][TODAY.getDay()]} ${TODAY.getDate()}:"]`) as HTMLElement;
      expect(todayCell.getAttribute('aria-label')).toContain('2 servicios');
      expect(todayCell.textContent).toContain('LT-1 · Limpieza');
      expect(todayCell.querySelector('.bg-error-container')).not.toBeNull(); // vencido
      expect(todayCell.querySelector('.bg-brand-accentLight')).not.toBeNull(); // programado
    });

    it('lists the services of a selected day and opens a plan from it', () => {
      click(host().querySelector('[aria-label^="' + ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb'][TODAY.getDay()] + ' ' + TODAY.getDate() + ':"]'));
      expect(store.selectDay).toHaveBeenCalledWith(dayKey(TODAY));
      render(state({ selectedDay: dayKey(TODAY) }));
      expect(host().querySelector('[aria-label="Servicios del día seleccionado"]')!.textContent).toContain('Firmware');
      click(host().querySelector('[aria-label="Servicios del día seleccionado"] button'));
      expect(store.selectPlan).toHaveBeenCalled();
    });

    it('navigates and switches scale through the store', () => {
      click(button('Hoy'));
      click(host().querySelector('[aria-label="Siguiente"]'));
      click(button('Semana'));
      expect(store.goToday).toHaveBeenCalled();
      expect(store.navigate).toHaveBeenCalledWith(1);
      expect(store.setMode).toHaveBeenCalledWith('week');
    });

    it('shows the next 30 days as a timeline with overdue first, and the pulse metrics with n and few-data notes', () => {
      const timeline = host().querySelector('[aria-label="Próximos 30 días"]')!.textContent!;
      expect(timeline.indexOf('Vencidos')).toBeLessThan(timeline.indexOf('Mañana'));
      const pulse = host().querySelector('[aria-label="Pulso del mantenimiento"]')!.textContent!;
      expect(pulse).toContain('n = 10');
      expect(pulse).toContain('pocos datos');
      expect(pulse).toContain('66,7%');
      expect(pulse).toContain('50%');
    });

    it('says so when metrics or the timeline are unavailable instead of showing zeros', () => {
      render(state({ overview: null, timeline: null }));
      expect(host().textContent).toContain('Las métricas no están disponibles');
      expect(host().textContent).toContain('La línea de tiempo no está disponible');
    });

    it('shows the empty-timeline illustration when nothing is scheduled', () => {
      render(state({ timeline: [] }));
      expect(host().querySelector('[aria-label="Próximos 30 días"] img[src$="columna-vacia.svg"]')).not.toBeNull();
    });

    it('reports a calendar error', () => {
      render(state({ calendarError: 'No se pudo cargar el calendario.' }));
      expect(host().querySelector('[role="alert"]')!.textContent).toContain('No se pudo cargar el calendario.');
    });

    it('plays the hero video muted, decorative and without images', () => {
    const video = host().querySelector('header video') as HTMLVideoElement;
    expect(video.getAttribute('src')).toBe('assets/videos/mantenimiento1.mp4');
    expect(video.getAttribute('poster')).toBe('assets/videos/mantenimiento-poster.jpg');
    expect(video.muted).toBeTrue();
    expect(video.closest('[aria-hidden="true"]')).not.toBeNull();
      expect(host().querySelector('header img')).toBeNull();
    });
  });

  describe('permissions', () => {
    it('shows the create actions to someone who can manage plans', async () => {
      await create(true);
      expect(button('Programar mantenimiento')).not.toBeNull();
      expect(host().querySelector('[aria-label="Programar mantenimiento"]')).not.toBeNull(); // acción flotante
    });

    it('hides them from a read-only user, including the detail actions', async () => {
      await create(false);
      expect(button('Programar mantenimiento')).toBeNull();
      expect(host().querySelector('button[aria-label="Programar mantenimiento"]')).toBeNull();
      render(state({ selectedId: 1, plan: plan(), history: { runs: [], reschedules: [] } }));
      expect(button('Marcar como hecho')).toBeNull();
      expect(button('Desactivar plan…')).toBeNull();
    });
  });

  describe('list view', () => {
    beforeEach(async () => {
      await create();
      render(state({ view: 'list', list: [plan(), plan({ id: 2, title: 'Vencido', next_due_at: addDays(TODAY, -3).toISOString() })], listTotal: 31 }));
    });

    it('shows dense rows with status chips and server pagination', () => {
      const rows = host().querySelectorAll('tbody tr');
      expect(rows.length).toBe(2);
      expect(rows[0].textContent).toContain('Limpieza interna');
      expect(rows[1].textContent).toContain('Vencido');
      expect(host().querySelector('nav[aria-label="Paginación"]')!.textContent).toContain('1–2 de 31');
      click(button('Siguiente'));
      expect(store.setListPage).toHaveBeenCalledWith(2);
    });

    it('sorts on the server when a header is pressed and announces it', () => {
      expect(host().querySelector('th[aria-sort="none"]')).not.toBeNull();
      click(button('Plan'));
      expect(store.setFilters).toHaveBeenCalledWith({ sort: 'title' });
      render(state({ view: 'list', list: [plan()], listTotal: 1, filters: { ...EMPTY_LIST_FILTERS, sort: '-next_due_at' } }));
      expect(host().querySelector('th[aria-sort="descending"]')).not.toBeNull();
    });

    it('offers to clear filters when nothing matches, with the empty illustration', () => {
      render(state({ view: 'list', list: [], listTotal: 0, filters: { ...EMPTY_LIST_FILTERS, status: 'overdue' } }));
      expect(host().textContent).toContain('Ningún plan coincide con los filtros');
      expect(host().querySelector('img[src$="cola-vacia.svg"]')).not.toBeNull();
      click(Array.from(host().querySelectorAll('button')).filter((b) => b.textContent?.includes('Limpiar')).pop()!);
      expect(store.clearFilters).toHaveBeenCalled();
    });

    it('opens a plan when its row is chosen', () => {
      click(host().querySelector('tbody tr'));
      expect(store.selectPlan).toHaveBeenCalledWith(1);
    });
  });

  describe('plan form', () => {
    beforeEach(async () => {
      await create();
      click(button('Programar mantenimiento'));
    });

    const submit = () => host().querySelector('form[role="dialog"] button[type="submit"]') as HTMLButtonElement;
    const fill = (overrides: Record<string, string> = {}) => {
      const values: Record<string, string> = { '#pf-title': 'Limpieza interna', '#pf-interval': '30', '#pf-remind': '3', ...overrides };
      for (const [selector, value] of Object.entries(values)) {
        type(selector, value);
      }
      const equipment = host().querySelector('#pf-equipment') as HTMLSelectElement;
      equipment.selectedIndex = 1;
      equipment.dispatchEvent(new Event('change'));
      fixture.detectChanges();
    };
    const message = (id: string) => host().querySelector(`#${id}`)!.textContent!.trim();

    it('starts with the submit button disabled and without errors shown', () => {
      expect(submit().disabled).toBeTrue();
      expect(message('pf-title-err')).toBe('');
    });

    it('never offers equipment that is retired or lost', () => {
      const options = Array.from(host().querySelectorAll('#pf-equipment option')).map((o) => o.textContent);
      expect(options.some((o) => o?.includes('LT-1'))).toBeTrue();
      expect(options.some((o) => o?.includes('LT-9'))).toBeFalse();
    });

    it('accepts a valid plan and sends it trimmed, with numbers as numbers', () => {
      fill({ '#pf-title': '  Limpieza interna  ', '#pf-hours': '1,5' });
      expect(submit().disabled).toBeFalse();
      click(submit());
      const payload = store.create.calls.mostRecent().args[0];
      expect(payload).toEqual(jasmine.objectContaining({
        equipment_id: 1, title: 'Limpieza interna', description: null, interval_days: 30, remind_days_before: 3, estimated_hours: 1.5,
      }));
      expect(new Date(payload.first_due_at).getTime()).toBeGreaterThan(Date.now());
    });

    it('explains each invalid value under its field in Spanish', () => {
      fill({ '#pf-title': '   ' });
      expect(message('pf-title-err')).toBe('Este campo es obligatorio.');
      fill({ '#pf-title': 'ab' });
      expect(message('pf-title-err')).toBe('Debe tener al menos 3 caracteres.');
      fill({ '#pf-interval': '-5' });
      expect(message('pf-interval-err')).toBe('Debe ser al menos 1.');
      fill({ '#pf-interval': '1.5' });
      expect(message('pf-interval-err')).toBe('Debe ser un número entero.');
      fill({ '#pf-interval': '30', '#pf-remind': '45' });
      expect(message('pf-remind-err')).toBe('El recordatorio no puede superar el intervalo entre servicios.');
      fill({ '#pf-remind': '3', '#pf-hours': '-2' });
      expect(message('pf-hours-err')).toBe('Escribe un número válido.');
      fill({ '#pf-hours': '1.234' });
      expect(message('pf-hours-err')).toBe('Usa como máximo 2 decimales.');
      fill({ '#pf-hours': '1000' });
      expect(message('pf-hours-err')).toBe('No puede ser mayor que 999.');
      expect(submit().disabled).toBeTrue();
      click(submit());
      expect(store.create).not.toHaveBeenCalled();
    });

    it('rejects a date in the past and an impossible one (the native control empties it)', () => {
      fill();
      type('#pf-due', toLocalInput(addDays(TODAY, -1)));
      expect(message('pf-due-err')).toBe('No se puede programar en el pasado.');
      expect(submit().disabled).toBeTrue();
      // El control nativo descarta un 30 de febrero (queda vacío); el validador cubre además el valor tecleado.
      type('#pf-due', '2027-02-30T09:00');
      expect(message('pf-due-err')).toBe('Este campo es obligatorio.');
      expect(submit().disabled).toBeTrue();
    });

    it('blocks a second submit while saving', () => {
      fill();
      render(state({ busy: true }));
      expect(submit().disabled).toBeTrue();
      expect(submit().textContent).toContain('Guardando');
    });

    it('shows the server message under the field when the backend refuses a value', () => {
      store.create.and.returnValue(of({ ok: false, fieldErrors: { first_due_at: 'La fecha no es válida.' } }));
      fill();
      click(submit());
      expect(message('pf-due-err')).toBe('La fecha no es válida.');
    });

    it('closes with Escape', () => {
      document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
      fixture.detectChanges();
      expect(host().querySelector('form[role="dialog"]')).toBeNull();
    });
  });

  describe('plan detail', () => {
    beforeEach(async () => {
      await create();
      render(state({ selectedId: 1, plan: plan({ next_due_at: addDays(TODAY, -2).toISOString() }), history: {
        runs: [{ id: 1, due_at: '2026-09-01T00:00:00Z', completed_at: '2026-09-02T00:00:00Z', on_time: false, actual_hours: '2.00' }],
        reschedules: [{ id: 1, old_due_at: '2026-09-10T00:00:00Z', new_due_at: '2026-09-20T00:00:00Z', reason: 'Equipo en uso', changed_at: '2026-09-05T00:00:00Z' }],
      } }));
    });

    it('shows the overdue state, the history and the reschedule reason', () => {
      const panel = host().querySelector('[aria-label="Detalle del plan"]')!.textContent!;
      expect(panel).toContain('Vencido');
      expect(panel).toContain('Con retraso');
      expect(panel).toContain('Equipo en uso');
    });

    it('completes a service with optional real hours, rejecting invalid ones', () => {
      click(button('Marcar como hecho'));
      const confirm = () => host().querySelector('#pd-hours')!.closest('form')!.querySelector('button[type=submit]') as HTMLButtonElement;
      type('#pd-hours', '-1');
      expect(confirm().disabled).toBeTrue();
      type('#pd-hours', '1.234');
      expect(host().querySelector('#pd-hours-err')!.textContent).toContain('2 decimales');
      type('#pd-hours', '2,5');
      click(confirm());
      expect(store.complete).toHaveBeenCalledWith(1, 2.5);
    });

    it('requires a future date to reschedule and sends the reason', () => {
      click(button('Reprogramar'));
      const confirm = () => host().querySelector('#pd-due')!.closest('form')!.querySelector('button[type=submit]') as HTMLButtonElement;
      expect(confirm().disabled).toBeTrue();
      type('#pd-due', toLocalInput(addDays(TODAY, -1)));
      expect(host().querySelector('#pd-due-err')!.textContent).toContain('pasado');
      type('#pd-due', toLocalInput(addDays(TODAY, 10)));
      type('#pd-reason', '   ');
      expect(host().querySelector('#pd-reason-err')!.textContent).toContain('solo espacios');
      expect(confirm().disabled).toBeTrue();
      type('#pd-reason', '  Equipo en uso  ');
      click(confirm());
      const [id, payload, message] = store.update.calls.mostRecent().args;
      expect(id).toBe(1);
      expect(payload.reschedule_reason).toBe('Equipo en uso');
      expect(new Date(payload.next_due_at as string).getTime()).toBeGreaterThan(Date.now());
      expect(message).toBe('Servicio reprogramado.');
    });

    it('asks for confirmation before deactivating a plan', () => {
      click(button('Desactivar plan…'));
      expect(store.update).not.toHaveBeenCalled();
      expect(host().textContent).toContain('¿Desactivar este plan?');
      click(button('Confirmar desactivación'));
      expect(store.update).toHaveBeenCalledWith(1, { is_active: false }, 'Plan desactivado.');
    });

    it('offers no actions on an inactive plan', () => {
      render(state({ selectedId: 1, plan: plan({ is_active: false }), history: { runs: [], reschedules: [] } }));
      expect(button('Marcar como hecho')).toBeNull();
      expect(host().textContent).toContain('Inactivo');
    });
  });

  describe('contrast inside the .tw-reset shell (AA, 4.5:1)', () => {
    beforeEach(() => create());
    const ratio = (el: Element) => {
      const style = getComputedStyle(el);
      return contrastRatio(flatten(style.color), flatten(style.backgroundColor, '#ffffff'));
    };

    it('keeps the glass call to action, the toggles and the period selector legible', () => {
      expect(ratio(button('Programar mantenimiento')!)).toBeGreaterThanOrEqual(WCAG_AA);
      for (const el of Array.from(host().querySelectorAll('[role="group"] button'))) {
        const style = getComputedStyle(el);
        const background = style.backgroundColor === 'rgba(0, 0, 0, 0)' ? '#ffffff' : flatten(style.backgroundColor);
        expect(contrastRatio(style.color, background)).withContext(el.textContent ?? '').toBeGreaterThanOrEqual(WCAG_AA);
      }
    });

    it('keeps the event chips legible', () => {
      for (const chip of Array.from(host().querySelectorAll('[aria-label$="servicios"] .truncate'))) {
        const style = getComputedStyle(chip);
        expect(contrastRatio(flatten(style.color), flatten(style.backgroundColor, '#ffffff'))).toBeGreaterThanOrEqual(WCAG_AA);
      }
    });
  });
});
