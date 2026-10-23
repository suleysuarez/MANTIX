import { Component } from '@angular/core';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { BehaviorSubject, of } from 'rxjs';

import { LocalProfileService } from '../../core/local-profile.service';
import { MaintenanceListItem, MaintenanceRequest } from '../../core/maintenance.service';
import {
  EMPTY_FILTERS, PendingRequestsState, PendingRequestsStore,
} from '../../core/pending-requests.store';
import { PriorityRef, QueueSummary } from '../../core/queue.service';
import { Technician } from '../../core/technicians.service';
import { ToastService } from '../../core/toast.service';
import { WorkflowState } from '../../core/workflow.service';
import { WCAG_AA, contrastRatio, flatten } from '../dashboard/contrast';
import { PendingRequestsComponent } from './pending-requests.component';

const iso = (hoursAgo: number) => new Date(Date.now() - hoursAgo * 3_600_000).toISOString();
const item = (id: number, hoursAgo = 2): MaintenanceListItem => ({
  id, ticket_number: `T-${id}`, equipment_id: 1, title: `Pantalla ${id}`, priority: 'high', category: 'network',
  status: 'submitted', created_at: iso(hoursAgo),
});
const technician = (id: number, available = true, active = true) =>
  ({ id, user_id: id, full_name: `Tec ${id}`, is_available: available, is_active: active }) as Technician;

/** Lo que el servidor dice del State Pattern: los estados de la bandeja y los pasos entre ellos. */
const WORKFLOW: WorkflowState[] = [
  { status: 'submitted', order: 1, allowed_targets: ['assigned', 'cancelled', 'triaged'], requires: [], terminal: false, in_queue: true },
  { status: 'triaged', order: 2, allowed_targets: ['assigned', 'cancelled'], requires: ['category', 'priority'], terminal: false, in_queue: true },
  { status: 'assigned', order: 3, allowed_targets: ['cancelled', 'in_progress'], requires: ['technician'], terminal: false, in_queue: true },
  { status: 'in_progress', order: 4, allowed_targets: ['resolved'], requires: [], terminal: false, in_queue: false },
];
const PRIORITIES: PriorityRef[] = [
  { code: 'urgent', name: 'Urgente', level: 4 }, { code: 'high', name: 'Alta', level: 3 },
  { code: 'medium', name: 'Media', level: 2 }, { code: 'low', name: 'Baja', level: 1 },
];
const col = (items: MaintenanceListItem[], total = items.length) => ({ items, total, page: 1, loading: false, failed: false });
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
    statuses: ['submitted', 'triaged', 'assigned'], workflow: WORKFLOW, priorities: PRIORITIES,
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

  beforeEach(async () => {
    subject = new BehaviorSubject(state());
    store = Object.assign(
      jasmine.createSpyObj('PendingRequestsStore', ['load', 'setFilters', 'clearFilters', 'setPeriod', 'loadMore', 'select', 'classify', 'assign', 'reject', 'move']),
      { state$: subject },
    );
    store.classify.and.returnValue(of({ ok: true, fieldErrors: {} }));
    store.assign.and.returnValue(of({ ok: true, fieldErrors: {} }));
    store.reject.and.returnValue(of({ ok: true, fieldErrors: {} }));
    store.move.and.returnValue(of({ ok: true }));
    TestBed.configureTestingModule({
      providers: [
        provideRouter([]),
        { provide: PendingRequestsStore, useValue: store },
        { provide: LocalProfileService, useValue: { can: () => Promise.resolve(true) } },
      ],
    });
    fixture = TestBed.createComponent(ShellHostComponent);
    document.body.appendChild(host());
    fixture.detectChanges();
    await fixture.whenStable(); // canManage (async permission check) enables dragging
    fixture.detectChanges();
  });

  afterEach(() => host().remove());

  it('draws one column per queue state of the workflow, not a fixed list', () => {
    const ids = Array.from(host().querySelectorAll('section[data-column]')).map((s) => s.getAttribute('data-column'));
    expect(ids).toEqual(['submitted', 'triaged', 'assigned']);
    expect(host().textContent).toContain('Recibidas');
    expect(host().textContent).toContain('Clasificadas');
    const cards = host().querySelectorAll('[aria-label="Tablero de solicitudes"] article[aria-pressed]');
    expect(cards[0].textContent).toContain('T-1');
    expect(cards[0].textContent).toContain('30 h');
  });

  it('shows a column the server adds to the queue without code changes', () => {
    const extra: WorkflowState = { status: 'waiting', order: 5, allowed_targets: [], requires: [], terminal: false, in_queue: true };
    render(state({ statuses: ['submitted', 'triaged', 'assigned', 'waiting'], workflow: [...WORKFLOW, extra], columns: { submitted: col([]), triaged: col([]), assigned: col([]), waiting: col([item(9)]) } }));
    expect(host().querySelector('section[data-column="waiting"]')!.textContent).toContain('T-9');
  });

  it('no longer offers the «más antiguas primero» order or mentions it', () => {
    expect(host().textContent).not.toContain('Más antiguas primero');
    expect(host().textContent).not.toContain('más antiguo aparece primero');
    expect(Array.from(host().querySelectorAll('#q-order option')).map((o) => o.getAttribute('value'))).toEqual(['newest', 'priority']);
  });

  it('shows each priority as a label read from the priorities table, wrapping instead of cutting', () => {
    const tag = host().querySelector('[aria-label="Tablero de solicitudes"] article span.rounded-full.break-words') as HTMLElement;
    expect(tag.textContent!.trim()).toBe('Alta'); // `name` of the table row, not a hard-coded label
    expect(tag.className).toContain('max-w-full');
  });

  it('lists the priorities of the table in the filter', () => {
    const options = Array.from(host().querySelectorAll('#q-priority option')).map((o) => o.textContent!.trim());
    expect(options).toEqual(['Todas', 'Urgente', 'Alta', 'Media', 'Baja']);
  });

  describe('dragging between columns (State Pattern)', () => {
    let toasts: ToastService;
    beforeEach(() => (toasts = TestBed.inject(ToastService)));

    const column = (status: string) => host().querySelector(`section[data-column="${status}"]`) as HTMLElement;
    const wrapper = (name: string) => Array.from(host().querySelectorAll<HTMLElement>('[draggable]')).find((el) => el.textContent?.includes(name))!;
    const drag = (type: string, target: HTMLElement, transfer: DataTransfer) => {
      target.dispatchEvent(new DragEvent(type, { bubbles: true, cancelable: true, dataTransfer: transfer }));
      fixture.detectChanges();
    };
    const dragAndDrop = (name: string, to: string) => {
      const transfer = new DataTransfer();
      drag('dragstart', wrapper(name), transfer);
      drag('dragover', column(to), transfer);
      drag('drop', column(to), transfer);
    };
    const dialog = () => host().querySelector('app-transition-dialog');
    const fill = (id: string, value: string) => {
      const el = host().querySelector(`#${id}`) as HTMLSelectElement;
      el.value = value;
      el.dispatchEvent(new Event('change'));
      fixture.detectChanges();
    };
    const press = (text: string) => {
      (Array.from(host().querySelectorAll('app-transition-dialog button')).find((b) => b.textContent?.trim() === text) as HTMLButtonElement).click();
      fixture.detectChanges();
    };
    const triagedOnly = () => state({ columns: { submitted: col([]), triaged: col([item(3)]), assigned: col([]) } });

    it('highlights only the destinations the workflow allows and dims the others', () => {
      render(triagedOnly());
      drag('dragstart', wrapper('T-3'), new DataTransfer()); // triaged -> assigned only (cancelled is not a column)
      expect(column('assigned').className).toContain('border-dashed');
      expect(column('submitted').className).toContain('opacity-40');
    });

    it('rejects an invalid step without calling the store and names the valid destinations', () => {
      render(triagedOnly());
      dragAndDrop('T-3', 'submitted');
      expect(store.move).not.toHaveBeenCalled();
      expect(column('triaged').textContent).toContain('T-3');
      const [message] = toasts.toasts().map((t) => t.message);
      expect(message).toContain('No se puede pasar T-3 de «Clasificadas» a «Recibidas».');
      expect(message).toContain('«Asignadas»');
    });

    it('asks for category and priority before classifying, starting from the card\'s own, and sends them', () => {
      dragAndDrop('T-1', 'triaged');
      expect(host().textContent).toContain('Clasificar solicitud');
      expect((host().querySelector('#td-category') as HTMLSelectElement).value).toBe('network');
      expect((host().querySelector('#td-priority') as HTMLSelectElement).value).toBe('high');
      press('Clasificar');
      expect(store.move).toHaveBeenCalledWith(jasmine.objectContaining({ id: 1 }), 'submitted', 'triaged', { category: 'network', priority: 'high' });
      expect(dialog()).toBeNull();
    });

    it('does not accept the assignment step without a technician (required data missing)', () => {
      dragAndDrop('T-1', 'assigned');
      expect(dialog()).not.toBeNull();
      const confirm = Array.from(host().querySelectorAll('app-transition-dialog button')).find((b) => b.textContent?.trim() === 'Asignar') as HTMLButtonElement;
      expect(confirm.disabled).toBeTrue();
      press('Asignar');
      expect(store.move).not.toHaveBeenCalled();
    });

    it('lists inactive and unavailable technicians as disabled options', () => {
      render(state({ technicians: [technician(1), technician(2, false), technician(3, true, false)] }));
      dragAndDrop('T-1', 'assigned');
      const options = Array.from((host().querySelector('#td-technician') as HTMLSelectElement).options);
      const inactive = options.find((o) => o.textContent!.includes('Tec 3'))!;
      expect(inactive.disabled).toBeTrue();
      expect(inactive.textContent).toContain('(inactivo)');
      expect(options.find((o) => o.textContent!.includes('Tec 2'))!.disabled).toBeTrue();
      expect(options.find((o) => o.textContent!.includes('Tec 1'))!.disabled).toBeFalse();
    });

    it('sends the chosen technician and keeps the card in the new column', () => {
      dragAndDrop('T-1', 'assigned');
      fill('td-technician', '1');
      press('Asignar');
      expect(store.move).toHaveBeenCalledWith(jasmine.objectContaining({ id: 1 }), 'submitted', 'assigned', { technicianId: 1 });
      expect(column('assigned').textContent).toContain('T-1');
    });

    it('sends the card back to its column when the dialog is cancelled', () => {
      dragAndDrop('T-1', 'assigned');
      press('Cancelar');
      expect(dialog()).toBeNull();
      expect(column('submitted').textContent).toContain('T-1');
      expect(column('assigned').textContent).not.toContain('T-1');
      expect(store.move).not.toHaveBeenCalled();
      expect(toasts.toasts()).toEqual([]);
    });

    it('returns the card and explains when the server rejects the step (inactive technician)', () => {
      store.move.and.returnValue(of({ ok: false, message: 'No se puede asignar a un técnico inactivo.' }));
      dragAndDrop('T-1', 'assigned');
      fill('td-technician', '1');
      press('Asignar');
      expect(column('submitted').textContent).toContain('T-1');
      expect(column('assigned').textContent).not.toContain('T-1');
      expect(toasts.toasts().map((t) => t.message)).toContain('No se puede asignar a un técnico inactivo.');
    });

    it('asks the store for the next page of a column from its «Cargar más» button', () => {
      render(state({ columns: { submitted: col([item(1)], 20), triaged: col([]), assigned: col([]) } }));
      click(button('Cargar más'));
      expect(store.loadMore).toHaveBeenCalledWith('submitted');
    });
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
    click(host().querySelector('[aria-label="Tablero de solicitudes"] article[aria-pressed]'));
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
    expect(host().querySelectorAll('[aria-label="Tablero de solicitudes"] article[aria-pressed]').length).toBe(2);
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
