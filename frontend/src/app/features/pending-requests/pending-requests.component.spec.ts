import { Component } from '@angular/core';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { BehaviorSubject, of } from 'rxjs';

import { MaintenanceListItem, MaintenanceRequest } from '../../core/maintenance.service';
import {
  EMPTY_FILTERS, PendingRequestsState, PendingRequestsStore, QUEUE_STATUSES,
} from '../../core/pending-requests.store';
import { QueueSummary } from '../../core/queue.service';
import { Technician } from '../../core/technicians.service';
import { WCAG_AA, contrastRatio, flatten } from '../dashboard/contrast';
import { PendingRequestsComponent } from './pending-requests.component';

const iso = (hoursAgo: number) => new Date(Date.now() - hoursAgo * 3_600_000).toISOString();
const item = (id: number, hoursAgo = 2): MaintenanceListItem => ({
  id, ticket_number: `T-${id}`, equipment_id: 1, title: `Pantalla ${id}`, priority: 'high', category: 'network',
  status: 'submitted', created_at: iso(hoursAgo),
});
const technician = (id: number, available = true) =>
  ({ id, user_id: id, full_name: `Tec ${id}`, is_available: available }) as Technician;
const detail = (status = 'submitted'): MaintenanceRequest => ({
  id: 1, ticket_number: 'T-1', equipment: { id: 1, asset_tag: 'LT-1', brand: 'Dell', model: 'X' },
  requested_by: { id: 9, full_name: 'Ana', email: 'a@x.co' }, title: 'Pantalla rota', description: 'No enciende',
  priority: 'high', category: 'network', status, resolution_summary: null, resolved_at: null, closed_at: null,
  created_at: iso(30), updated_at: iso(1), current_assignment: null,
  status_history: [{ id: 1, from_status: null, to_status: 'submitted', changed_at: iso(30), notes: null }],
  allowed_next_statuses: ['triaged', 'cancelled'],
});

function state(overrides: Partial<PendingRequestsState> = {}): PendingRequestsState {
  const column = (items: MaintenanceListItem[]) => ({ items, total: items.length, page: 1, loading: false, failed: false });
  return {
    filters: EMPTY_FILTERS,
    filterError: '',
    columns: { submitted: column([item(1, 30), item(2)]), triaged: column([]), assigned: column([]) },
    period: '30d', summary: null, summaryLoading: false,
    categories: [{ code: 'network', name: 'Red y conectividad' }],
    technicians: [technician(1), technician(2, false)],
    equipmentById: new Map(), loading: false, error: '', selectedId: null, detail: null, detailLoading: false,
    detailError: '', busy: false, ...overrides,
  };
}

@Component({
  standalone: true,
  imports: [PendingRequestsComponent],
  template: '<div class="tw-reset"><app-pending-requests /></div>',
})
class ShellHostComponent {}

describe('PendingRequestsComponent', () => {
  let subject: BehaviorSubject<PendingRequestsState>;
  let store: jasmine.SpyObj<PendingRequestsStore> & { state$: BehaviorSubject<PendingRequestsState> };
  let fixture: ComponentFixture<ShellHostComponent>;

  const host = () => fixture.nativeElement as HTMLElement;
  const render = (value: PendingRequestsState) => {
    subject.next(value);
    fixture.detectChanges();
  };
  const click = (el: Element | null) => {
    (el as HTMLElement).click();
    fixture.detectChanges();
  };
  const button = (text: string) =>
    Array.from(host().querySelectorAll('button')).find((b) => b.textContent?.includes(text)) ?? null;

  beforeEach(() => {
    subject = new BehaviorSubject(state());
    store = Object.assign(
      jasmine.createSpyObj('PendingRequestsStore', ['load', 'setFilters', 'clearFilters', 'setPeriod', 'loadMore', 'select', 'classify', 'assign', 'reject']),
      { state$: subject },
    );
    store.classify.and.returnValue(of({ ok: true, fieldErrors: {} }));
    store.assign.and.returnValue(of({ ok: true, fieldErrors: {} }));
    store.reject.and.returnValue(of({ ok: true, fieldErrors: {} }));
    TestBed.configureTestingModule({ providers: [provideRouter([]), { provide: PendingRequestsStore, useValue: store }] });
    fixture = TestBed.createComponent(ShellHostComponent);
    document.body.appendChild(host());
    fixture.detectChanges();
  });

  afterEach(() => host().remove());

  it('shows the queue as three columns with the oldest request first', () => {
    const columns = host().querySelectorAll('[aria-label="Tablero de solicitudes"] > div > div');
    expect(columns.length).toBe(QUEUE_STATUSES.length);
    expect(host().textContent).toContain('Recibidas');
    expect(host().textContent).toContain('Clasificadas');
    const cards = host().querySelectorAll('[aria-label="Tablero de solicitudes"] button[aria-pressed]');
    expect(cards[0].textContent).toContain('T-1');
    expect(cards[0].textContent).toContain('30 h');
  });

  it('plays the hero illustration muted and looping, hidden from assistive technology', () => {
    const video = host().querySelector('header video') as HTMLVideoElement;
    expect(video.getAttribute('src')).toBe('assets/videos/mensajes.mp4');
    expect(video.getAttribute('poster')).toBe('assets/videos/mensajes-poster.jpg');
    expect(video.muted).toBeTrue();
    expect(video.closest('[aria-hidden="true"]')).not.toBeNull();
    expect(host().querySelector('[data-placeholder="solicitudes-hero.svg"]')).toBeNull();
  });

  it('opens the detail panel through the store when a card is picked', () => {
    click(host().querySelector('[aria-label="Tablero de solicitudes"] button[aria-pressed]'));
    expect(store.select).toHaveBeenCalledWith(1);
  });

  it('shows the empty-queue illustration and a positive message when nothing is pending', () => {
    const empty = { items: [], total: 0, page: 1, loading: false, failed: false };
    render(state({ columns: { submitted: empty, triaged: empty, assigned: empty } }));
    expect(host().textContent).toContain('La bandeja está al día');
    const image = host().querySelector('img[src$="cola-vacia.svg"]') as HTMLImageElement;
    expect(image).not.toBeNull();
    expect(image.getAttribute('alt')).toBe(''); // decorativa: el título ya dice lo mismo
  });

  it('shows the small illustration in a single empty column and keeps the others as cards', () => {
    expect(host().querySelectorAll('img[src$="columna-vacia.svg"]').length).toBe(2); // triaged + assigned
    expect(host().querySelectorAll('[aria-label="Tablero de solicitudes"] button[aria-pressed]').length).toBe(2);
  });

  it('offers to clear the filters when they leave nothing to show', () => {
    const empty = { items: [], total: 0, page: 1, loading: false, failed: false };
    render(state({ filters: { ...EMPTY_FILTERS, search: 'zzz' }, columns: { submitted: empty, triaged: empty, assigned: empty } }));
    expect(host().textContent).toContain('Ninguna solicitud coincide con los filtros');
    click(Array.from(host().querySelectorAll('button')).filter((b) => b.textContent?.includes('Limpiar filtros')).pop()!);
    expect(store.clearFilters).toHaveBeenCalled();
  });

  it('says the metrics are unavailable instead of showing zeros', () => {
    expect(host().textContent).toContain('Las métricas no están disponibles');
  });

  it('shows rates with n and the few-data note, and dashes when nothing was decided', () => {
    const summary = {
      pending_total: 3, unassigned: 2, oldest_wait_hours: 50, median_wait_hours: 9, by_priority: [], by_category: [],
      triage_time: { value: 3, previous: 6, change_pct: -50, sample_size: 3, low_sample: true, median_hours: 2 },
      decisions: { approved: 2, rejected: 1, sample_size: 3, low_sample: true, approval_rate_pct: 66.7, rejection_rate_pct: 33.3, previous_approval_rate_pct: null, change_pct: null },
    } as unknown as QueueSummary;
    render(state({ summary }));
    expect(host().textContent).toContain('n = 3');
    expect(host().textContent).toContain('pocos datos');
    expect(host().textContent).toContain('66,7%');
    render(state({ summary: { ...summary, triage_time: { ...summary.triage_time, value: null, median_hours: null, sample_size: 0, low_sample: false }, decisions: { ...summary.decisions, approval_rate_pct: null, sample_size: 0, low_sample: false } } }));
    expect(host().textContent).not.toContain('pocos datos');
  });

  describe('detail panel', () => {
    beforeEach(() => render(state({ selectedId: 1, detail: detail() })));

    const choose = (id: string, value: string) => {
      const select = host().querySelector(id) as HTMLSelectElement;
      select.value = value;
      select.dispatchEvent(new Event('change'));
      fixture.detectChanges();
    };
    const type = (selector: string, value: string) => {
      const field = host().querySelector(selector) as HTMLTextAreaElement;
      field.value = value;
      field.dispatchEvent(new Event('input'));
      fixture.detectChanges();
    };
    const submitClassify = () => host().querySelector('form[aria-label="Clasificación"] button[type=submit]') as HTMLButtonElement;

    it('starts from the current category and priority and classifies with them', () => {
      expect((host().querySelector('#cls-category') as HTMLSelectElement).value).toBe('network');
      expect((host().querySelector('#cls-priority') as HTMLSelectElement).value).toBe('high');
      type('#cls-notes', '  Visita en sitio ');
      click(submitClassify());
      expect(store.classify).toHaveBeenCalledWith(1, { category: 'network', priority: 'high', notes: 'Visita en sitio' });
    });

    it('requires category and priority before classifying', () => {
      choose('#cls-category', '');
      expect(submitClassify().disabled).toBeTrue();
      choose('#cls-category', 'network');
      choose('#cls-priority', '');
      expect(submitClassify().disabled).toBeTrue();
      choose('#cls-priority', 'low');
      expect(submitClassify().disabled).toBeFalse();
      click(submitClassify());
      expect(store.classify).toHaveBeenCalledWith(1, { category: 'network', priority: 'low', notes: null });
    });

    it('limits the note to 500 characters', () => {
      type('#cls-notes', 'x'.repeat(501));
      expect(host().querySelector('form[aria-label="Clasificación"]')!.textContent).toContain('como máximo 500 caracteres');
      expect(submitClassify().disabled).toBeTrue();
    });

    it('blocks a second submit while an action is running', () => {
      render(state({ selectedId: 1, detail: detail(), busy: true }));
      expect(submitClassify().disabled).toBeTrue();
    });

    it('offers to reclassify a triaged request but not one that is assigned', () => {
      render(state({ selectedId: 1, detail: detail('triaged') }));
      expect(host().querySelector('form[aria-label="Clasificación"]')!.textContent).toContain('Guardar clasificación');
      expect(button('Asignar')).not.toBeNull();
      render(state({ selectedId: 1, detail: detail('assigned') }));
      expect(host().querySelector('form[aria-label="Clasificación"]')).toBeNull();
      expect(button('Asignar')).not.toBeNull();
    });

    it('requires a technician before assigning and warns about unavailable ones', () => {
      const select = host().querySelector('#assign-tech') as HTMLSelectElement;
      const submit = Array.from(host().querySelectorAll('form button[type=submit]')).find((b) => b.textContent?.includes('Asignar')) as HTMLButtonElement;
      expect(submit.disabled).toBeTrue();
      select.selectedIndex = 2; // Tec 2, no disponible
      select.dispatchEvent(new Event('change'));
      fixture.detectChanges();
      expect(submit.disabled).toBeFalse();
      expect(host().textContent).toContain('figura como no disponible');
      click(submit);
      expect(store.assign).toHaveBeenCalledWith(1, 2);
    });

    describe('rejection', () => {
      const open = () => click(button('Rechazar…'));
      const reason = () => host().querySelector('#reject-reason') as HTMLTextAreaElement;
      const confirm = () => button('Confirmar rechazo') as HTMLButtonElement;
      const type = (value: string) => {
        reason().value = value;
        reason().dispatchEvent(new Event('input'));
        reason().dispatchEvent(new Event('blur'));
        fixture.detectChanges();
      };

      it('asks for a reason first, with a destructive-action warning', () => {
        expect(host().querySelector('#reject-reason')).toBeNull();
        open();
        expect(host().textContent).toContain('no se puede deshacer');
        expect(confirm().disabled).toBeTrue();
      });

      it('keeps the confirm button disabled and explains why for empty, blank and short reasons', () => {
        open();
        for (const [value, message] of [
          ['', 'Escribe el motivo del rechazo.'],
          ['     ', 'Escribe el motivo del rechazo.'],
          ['abcd', 'El motivo debe tener al menos 5 caracteres.'],
        ]) {
          type(value);
          expect(confirm().disabled).withContext(`"${value}"`).toBeTrue();
          expect(host().querySelector('#reject-reason-help')!.textContent).toContain(message);
        }
        click(confirm());
        expect(store.reject).not.toHaveBeenCalled();
      });

      it('sends the trimmed reason once it is valid', () => {
        open();
        type('   Duplicado del T-9  ');
        expect(confirm().disabled).toBeFalse();
        click(confirm());
        expect(store.reject).toHaveBeenCalledOnceWith(1, 'Duplicado del T-9');
      });

      it('shows the server message under the field when the backend refuses the reason', () => {
        store.reject.and.returnValue(of({ ok: false, fieldErrors: { reason: 'Debe tener al menos 5 caracteres.' } }));
        open();
        type('Motivo válido');
        click(confirm());
        expect(host().querySelector('#reject-reason-help')!.textContent).toContain('Debe tener al menos 5 caracteres.');
      });

      it('blocks everything while an action is running (no double submit)', () => {
        open();
        type('Motivo válido');
        render(state({ selectedId: 1, detail: detail(), busy: true }));
        expect(confirm().disabled).toBeTrue();
      });
    });

    it('tells the user a request that left the queue can no longer be actioned', () => {
      render(state({ selectedId: 1, detail: detail('cancelled') }));
      expect(host().textContent).toContain('Ya no está en la bandeja');
      expect(button('Rechazar…')).toBeNull();
    });
  });

  describe('contrast inside the .tw-reset shell (AA, 4.5:1)', () => {
    const ratio = (el: Element) => {
      const style = getComputedStyle(el);
      return contrastRatio(flatten(style.color), flatten(style.backgroundColor, '#ffffff'));
    };

    it('keeps the glass primary button legible, with and without backdrop-filter', () => {
      render(state({ selectedId: 1, detail: detail() }));
      const primary = button('Clasificar solicitud')!;
      expect(ratio(primary)).toBeGreaterThanOrEqual(WCAG_AA);
      // Respaldo sólido: el fondo sin transparencia también cumple.
      expect(contrastRatio('#ffffff', '#3E5C76')).toBeGreaterThanOrEqual(WCAG_AA);
    });

    it('keeps the period selector and the destructive buttons legible', () => {
      render(state({ selectedId: 1, detail: detail() }));
      for (const el of Array.from(host().querySelectorAll('[aria-label="Periodo de las métricas"] button'))) {
        const style = getComputedStyle(el);
        const background = style.backgroundColor === 'rgba(0, 0, 0, 0)' ? '#ffffff' : flatten(style.backgroundColor);
        expect(contrastRatio(style.color, background)).withContext(el.textContent ?? '').toBeGreaterThanOrEqual(WCAG_AA);
      }
      click(button('Rechazar…'));
      const confirm = button('Confirmar rechazo')!;
      expect(ratio(confirm)).toBeGreaterThanOrEqual(WCAG_AA);
    });
  });
});
