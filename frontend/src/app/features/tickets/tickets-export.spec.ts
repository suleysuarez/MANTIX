import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { BehaviorSubject, Subject, of } from 'rxjs';

import { ExportService } from '../../core/export.service';
import { LocalProfileService } from '../../core/local-profile.service';
import { QueueService } from '../../core/queue.service';
import { TechniciansService } from '../../core/technicians.service';
import { EMPTY_FILTERS, TicketsState, TicketsStore } from '../../core/tickets.store';
import { TicketsComponent } from './tickets.component';

function state(filters = EMPTY_FILTERS): TicketsState {
  return {
    items: [], all: [], equipment: [], filters, loading: false, saving: false, error: '', filterError: '', page: 0, pageSize: 10, hasNext: false,
  };
}

describe('Tickets screen: export to PDF and Excel', () => {
  let subject: BehaviorSubject<TicketsState>;
  let api: jasmine.SpyObj<ExportService>;

  function create() {
    subject = new BehaviorSubject(state());
    api = jasmine.createSpyObj('ExportService', ['options', 'count', 'export']);
    api.options.and.returnValue(of({ report: 'tickets', title: 'T', columns: [], formats: ['pdf', 'xlsx'], max_rows: 10_000, warn_rows: 2_000, max_range_days: 366 }));
    api.count.and.returnValue(of({ total: 5, max_rows: 10_000, warn_rows: 2_000, over_limit: false, large: false }));
    const store = Object.assign(jasmine.createSpyObj('TicketsStore', ['load', 'setFilters', 'clearFilters', 'setPage']), {
      state$: subject,
      ticketCreated$: new Subject<number>(),
    });
    TestBed.configureTestingModule({
      providers: [
        provideRouter([]),
        { provide: TicketsStore, useValue: store },
        { provide: ExportService, useValue: api },
        { provide: LocalProfileService, useValue: { can: () => Promise.resolve(true) } },
        { provide: TechniciansService, useValue: { list: () => of([]) } },
        { provide: QueueService, useValue: { categories: () => of([]) } },
      ],
    });
    const fixture = TestBed.createComponent(TicketsComponent);
    fixture.detectChanges();
    return fixture;
  }

  const exportButton = (root: HTMLElement) =>
    Array.from(root.querySelectorAll('header button')).find((b) => b.textContent?.includes('Exportar')) as HTMLButtonElement;

  it('has an Exportar button in the header (and no longer the page-only CSV one)', () => {
    const root = create().nativeElement as HTMLElement;
    expect(exportButton(root)).toBeDefined();
    expect(root.textContent).not.toContain('Exportar CSV');
    expect(root.querySelector('app-export-drawer')).toBeNull();
  });

  it('opens the drawer starting from the filters of the screen', async () => {
    const fixture = create();
    const root = fixture.nativeElement as HTMLElement;
    subject.next(state({ ...EMPTY_FILTERS, status: 'resolved', priority: 'high', dateFrom: '2026-10-01', dateTo: '2026-10-14' }));
    fixture.detectChanges();
    exportButton(root).click();
    fixture.detectChanges();
    expect(root.querySelector('app-export-drawer')).not.toBeNull();
    await new Promise((resolve) => setTimeout(resolve, 380));
    fixture.detectChanges();
    const filters = api.count.calls.mostRecent().args[1];
    expect(api.count.calls.mostRecent().args[0]).toBe('tickets');
    expect(filters.statuses).toEqual(['resolved']);
    expect(filters.priorities).toEqual(['high']);
    expect(filters.date_from).toBeDefined();
    expect(root.querySelector('[aria-label="Estado"] [aria-pressed="true"]')!.textContent).toContain('Resuelto');
    root.querySelector<HTMLElement>('[aria-label="Cerrar panel de exportación"]')!.click();
    fixture.detectChanges();
    expect(root.querySelector('app-export-drawer')).toBeNull();
  });
});
