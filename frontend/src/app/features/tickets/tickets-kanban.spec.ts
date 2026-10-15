import { HttpErrorResponse } from '@angular/common/http';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { BehaviorSubject, Subject, of, throwError } from 'rxjs';

import { ExportService } from '../../core/export.service';
import { LocalProfileService } from '../../core/local-profile.service';
import { MaintenanceListItem, MaintenanceRequest } from '../../core/maintenance.service';
import { QueueService } from '../../core/queue.service';
import { Technician, TechniciansService } from '../../core/technicians.service';
import { TicketTransitionService } from '../../core/ticket-transitions.service';
import { EMPTY_FILTERS, TicketsState, TicketsStore } from '../../core/tickets.store';
import { ToastService } from '../../core/toast.service';
import { WorkflowService, WorkflowState } from '../../core/workflow.service';
import { TicketsComponent } from './tickets.component';

/** Lo que el servidor dice del State Pattern: los estados, sus pasos y lo que exige cada uno. */
const WORKFLOW: WorkflowState[] = [
  { status: 'submitted', order: 1, allowed_targets: ['assigned', 'cancelled', 'triaged'], requires: [], terminal: false },
  { status: 'triaged', order: 2, allowed_targets: ['assigned', 'cancelled'], requires: ['category', 'priority'], terminal: false },
  { status: 'assigned', order: 3, allowed_targets: ['cancelled', 'in_progress'], requires: ['technician'], terminal: false },
  { status: 'in_progress', order: 4, allowed_targets: ['cancelled', 'resolved', 'waiting'], requires: [], terminal: false },
  { status: 'waiting', order: 5, allowed_targets: ['cancelled', 'in_progress'], requires: [], terminal: false },
  { status: 'resolved', order: 6, allowed_targets: ['closed', 'in_progress'], requires: ['resolution_summary'], terminal: false },
  { status: 'closed', order: 7, allowed_targets: [], requires: [], terminal: true },
  { status: 'cancelled', order: 8, allowed_targets: [], requires: ['reason'], terminal: true },
];

const ticket = (id: number, status: string): MaintenanceListItem =>
  ({ id, ticket_number: `T-${id}`, equipment_id: 1, title: `Pantalla ${id}`, priority: 'high', category: 'network', status, created_at: '2026-10-14T10:00:00Z' }) as MaintenanceListItem;

function state(items: MaintenanceListItem[]): TicketsState {
  return { items, all: items, equipment: [], filters: EMPTY_FILTERS, loading: false, saving: false, error: '', filterError: '', page: 0, pageSize: 10, hasNext: false };
}

describe('Tickets kanban (shared board + State Pattern)', () => {
  let fixture: ComponentFixture<TicketsComponent>;
  let store: jasmine.SpyObj<TicketsStore>;
  let transitions: jasmine.SpyObj<TicketTransitionService>;
  let toasts: ToastService;

  const root = () => fixture.nativeElement as HTMLElement;
  const render = () => fixture.detectChanges();
  const column = (status: string) => root().querySelector(`section[data-column="${status}"]`) as HTMLElement;
  const cardsOf = (status: string) => Array.from(column(status).querySelectorAll('article')).map((a) => a.textContent!.match(/T-\d+/)![0]);
  const wrapper = (name: string) => Array.from(root().querySelectorAll<HTMLElement>('[draggable]')).find((el) => el.textContent?.includes(name))!;
  const drag = (type: string, target: HTMLElement, transfer: DataTransfer) => {
    target.dispatchEvent(new DragEvent(type, { bubbles: true, cancelable: true, dataTransfer: transfer }));
    render();
  };
  const dragAndDrop = (name: string, to: string) => {
    const transfer = new DataTransfer();
    drag('dragstart', wrapper(name), transfer);
    drag('dragover', column(to), transfer);
    drag('drop', column(to), transfer);
  };
  const dialog = () => root().querySelector('app-transition-dialog');
  const fill = (id: string, value: string) => {
    const el = root().querySelector(`#${id}`) as HTMLInputElement;
    el.value = value;
    el.dispatchEvent(new Event(el.tagName === 'SELECT' ? 'change' : 'input'));
    render();
  };
  const press = (text: string) => {
    (Array.from(root().querySelectorAll('app-transition-dialog button')).find((b) => b.textContent?.trim() === text) as HTMLButtonElement).click();
    render();
  };

  function create(items: MaintenanceListItem[], view: 'table' | 'kanban' = 'kanban'): void {
    transitions = jasmine.createSpyObj('TicketTransitionService', ['move']);
    transitions.move.and.returnValue(of({} as MaintenanceRequest));
    store = Object.assign(jasmine.createSpyObj('TicketsStore', ['load', 'setFilters', 'clearFilters', 'setPage', 'refresh']), {
      state$: new BehaviorSubject(state(items)),
      ticketCreated$: new Subject<number>(),
    });
    TestBed.configureTestingModule({
      providers: [
        provideRouter([]),
        { provide: TicketsStore, useValue: store },
        { provide: TicketTransitionService, useValue: transitions },
        { provide: WorkflowService, useValue: { states: () => of(WORKFLOW) } },
        { provide: ExportService, useValue: jasmine.createSpyObj('ExportService', ['options', 'count', 'export']) },
        { provide: LocalProfileService, useValue: { can: () => Promise.resolve(true) } },
        { provide: TechniciansService, useValue: { list: () => of([{ id: 4, full_name: 'Luis Gómez', is_available: true }, { id: 5, full_name: 'Marta Ruiz', is_available: false }] as Technician[]) } },
        { provide: QueueService, useValue: { categories: () => of([{ code: 'network', name: 'Redes' }]) } },
      ],
    });
    toasts = TestBed.inject(ToastService);
    fixture = TestBed.createComponent(TicketsComponent);
    document.body.appendChild(root());
    render();
    if (view === 'kanban') {
      (Array.from(root().querySelectorAll('button')).find((b) => b.textContent?.includes('Kanban')) as HTMLButtonElement).click();
      render();
    }
  }

  afterEach(() => root().remove());

  describe('columns come from the server', () => {
    beforeEach(() => create([ticket(1, 'submitted'), ticket(2, 'in_progress'), ticket(3, 'closed')]));

    it('draws one column per state of the workflow, in its order, including cancelled', () => {
      const ids = Array.from(root().querySelectorAll('section[data-column]')).map((s) => s.getAttribute('data-column'));
      expect(ids).toEqual(WORKFLOW.map((s) => s.status));
      expect(cardsOf('submitted')).toEqual(['T-1']);
      expect(cardsOf('in_progress')).toEqual(['T-2']);
    });

    it('does not let a ticket in a final state be dragged', () => {
      expect(wrapper('T-3').getAttribute('draggable')).toBe('false');
      expect(wrapper('T-1').getAttribute('draggable')).toBe('true');
    });

    it('highlights only the destinations the State Pattern allows', () => {
      drag('dragstart', wrapper('T-2'), new DataTransfer());
      expect(column('resolved').className).toContain('border-dashed');
      expect(column('waiting').className).toContain('border-dashed');
      expect(column('submitted').className).toContain('opacity-40');
      expect(column('closed').className).toContain('opacity-40');
    });
  });

  describe('a valid step with no data needed', () => {
    beforeEach(() => create([ticket(2, 'in_progress')]));

    it('moves at once, calls the API and refreshes the list', () => {
      dragAndDrop('T-2', 'waiting');
      expect(dialog()).toBeNull();
      expect(transitions.move).toHaveBeenCalledWith(2, 'in_progress', 'waiting', {});
      expect(cardsOf('waiting')).toEqual(['T-2']);
      expect(store.refresh).toHaveBeenCalled();
      expect(toasts.toasts().map((t) => t.message)).toContain('T-2 pasó a «En espera».');
    });

    it('returns the card and explains when the server rejects it', () => {
      transitions.move.and.returnValue(throwError(() => new HttpErrorResponse({ status: 409, error: { code: 'conflict', detail: 'cannot transition from x to y' } })));
      dragAndDrop('T-2', 'waiting');
      expect(cardsOf('in_progress')).toEqual(['T-2']);
      expect(cardsOf('waiting')).toEqual([]);
      expect(toasts.toasts().map((t) => t.message)).toContain('Ese cambio de estado no está permitido desde el estado actual.');
      expect(store.refresh).not.toHaveBeenCalled();
    });
  });

  describe('an invalid step', () => {
    beforeEach(() => create([ticket(1, 'submitted')]));

    it('keeps the card, never calls the API and names the valid destinations', () => {
      dragAndDrop('T-1', 'resolved');
      expect(transitions.move).not.toHaveBeenCalled();
      expect(cardsOf('submitted')).toEqual(['T-1']);
      const [message] = toasts.toasts().map((t) => t.message);
      expect(message).toContain('No se puede pasar T-1 de «Enviado» a «Resuelto».');
      expect(message).toContain('Desde ahí solo puede ir a');
      expect(message).toContain('«En triaje»');
    });
  });

  describe('steps that need data', () => {
    it('asks for the technician when moving to Asignado, and only lists the available ones as options', () => {
      create([ticket(1, 'submitted')]);
      dragAndDrop('T-1', 'assigned');
      expect(dialog()).not.toBeNull();
      expect(root().textContent).toContain('Asignar técnico');
      expect(transitions.move).not.toHaveBeenCalled();
      expect(cardsOf('assigned')).toEqual(['T-1']); // shown while the dialog is open
      const options = Array.from((root().querySelector('#td-technician') as HTMLSelectElement).options);
      expect(options.find((o) => o.textContent!.includes('Marta Ruiz'))!.disabled).toBeTrue();
      fill('td-technician', '4');
      press('Asignar');
      expect(transitions.move).toHaveBeenCalledWith(1, 'submitted', 'assigned', { technicianId: 4 });
      expect(dialog()).toBeNull();
      expect(cardsOf('assigned')).toEqual(['T-1']);
    });

    it('sends the card back to its column when the dialog is cancelled', () => {
      create([ticket(1, 'submitted')]);
      dragAndDrop('T-1', 'assigned');
      press('Cancelar');
      expect(dialog()).toBeNull();
      expect(cardsOf('submitted')).toEqual(['T-1']);
      expect(cardsOf('assigned')).toEqual([]);
      expect(transitions.move).not.toHaveBeenCalled();
      expect(toasts.toasts()).toEqual([]);
    });

    it('does not accept the technician step without a technician', () => {
      create([ticket(1, 'submitted')]);
      dragAndDrop('T-1', 'assigned');
      expect((Array.from(root().querySelectorAll('app-transition-dialog button')).find((b) => b.textContent?.trim() === 'Asignar') as HTMLButtonElement).disabled).toBeTrue();
      press('Asignar');
      expect(transitions.move).not.toHaveBeenCalled();
    });

    it('returns the card and shows the server message when an inactive technician is rejected', () => {
      create([ticket(1, 'submitted')]);
      transitions.move.and.returnValue(throwError(() => new HttpErrorResponse({ status: 409, error: { code: 'conflict', detail: 'cannot assign a ticket to an inactive technician' } })));
      dragAndDrop('T-1', 'assigned');
      fill('td-technician', '4');
      press('Asignar');
      expect(dialog()).toBeNull();
      expect(cardsOf('submitted')).toEqual(['T-1']);
      expect(toasts.toasts().map((t) => t.message)).toContain('No se puede asignar a un técnico inactivo.');
    });

    it('asks for the resolution summary when resolving', () => {
      create([ticket(2, 'in_progress')]);
      dragAndDrop('T-2', 'resolved');
      expect(root().textContent).toContain('Resolver ticket');
      fill('td-summary', 'Se reemplazó el SSD.');
      press('Resolver');
      expect(transitions.move).toHaveBeenCalledWith(2, 'in_progress', 'resolved', { resolutionSummary: 'Se reemplazó el SSD.' });
    });

    it('asks for a reason when cancelling', () => {
      create([ticket(2, 'in_progress')]);
      dragAndDrop('T-2', 'cancelled');
      fill('td-reason', 'Ya no hace falta');
      press('Cancelar ticket');
      expect(transitions.move).toHaveBeenCalledWith(2, 'in_progress', 'cancelled', { reason: 'Ya no hace falta' });
    });

    it('asks for category and priority when classifying, starting from the ticket\'s own', () => {
      create([ticket(1, 'submitted')]);
      dragAndDrop('T-1', 'triaged');
      expect((root().querySelector('#td-category') as HTMLSelectElement).value).toBe('network');
      expect((root().querySelector('#td-priority') as HTMLSelectElement).value).toBe('high');
      press('Clasificar');
      expect(transitions.move).toHaveBeenCalledWith(1, 'submitted', 'triaged', { category: 'network', priority: 'high' });
    });

    it('blocks a second submit while the server is answering', () => {
      create([ticket(1, 'submitted')]);
      const gate = new Subject<MaintenanceRequest>();
      transitions.move.and.returnValue(gate);
      dragAndDrop('T-1', 'assigned');
      fill('td-technician', '4');
      press('Asignar');
      render();
      press('Guardando…');
      expect(transitions.move).toHaveBeenCalledTimes(1);
    });
  });

  it('offers «Mover a…» with the valid destinations as the keyboard alternative', () => {
    create([ticket(2, 'in_progress')]);
    (wrapper('T-2').querySelector('button[aria-haspopup="menu"]') as HTMLButtonElement).click();
    render();
    const items = Array.from(root().querySelectorAll('[role="menuitem"]')).map((b) => b.textContent!.trim());
    expect(items).toEqual(['Cancelado', 'Resuelto', 'En espera']);
  });

  describe('recent tickets block (uses the whole width, nothing is cut)', () => {
    const long = 'Pantalla rota en la sala de juntas del tercer piso, con líneas verticales y parpadeo al conectar el cable HDMI al proyector';

    it('no longer shares the row with a fixed 320 px column: the list takes the full width', () => {
      create([{ ...ticket(1, 'submitted'), title: long }], 'table');
      expect(root().innerHTML).not.toContain('320px');
      const aside = root().querySelector('aside')!;
      expect(aside.className).toContain('grid');
      expect(aside.parentElement!.firstElementChild!.contains(aside)).toBeFalse(); // below the list, not beside it
    });

    it('wraps a long title in two lines with the full text as tooltip instead of truncating it', () => {
      create([{ ...ticket(1, 'submitted'), title: long }], 'table');
      const title = root().querySelector('tbody p[title]') as HTMLElement;
      expect(title.getAttribute('title')).toBe(long);
      expect(title.className).toContain('line-clamp-2');
      expect(title.className).not.toContain('truncate');
      expect(title.className).not.toContain('max-w-sm');
    });

    it('has no fixed minimum widths or no-wrap cells that would push the table sideways', () => {
      create([ticket(1, 'submitted')], 'table');
      const table = root().querySelector('table')!;
      expect(table.innerHTML).not.toContain('min-w-[');
      // only the short columns (code, chips) stay on one line; title, equipment and date can wrap
      for (const column of [2, 3, 6]) {
        expect(table.querySelector(`tbody tr td:nth-child(${column})`)!.className).withContext(`column ${column}`).not.toContain('whitespace-nowrap');
      }
    });

    it('keeps the full text of the equipment as tooltip too', () => {
      create([ticket(1, 'submitted')], 'table');
      expect(root().querySelector('tbody td span[title]')).not.toBeNull();
    });
  });
});
