import { ComponentFixture, TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { BehaviorSubject, Subject, of } from 'rxjs';

import { ExportService } from '../../core/export.service';
import { LocalProfileService } from '../../core/local-profile.service';
import { QueueService } from '../../core/queue.service';
import { Technician, TechniciansService } from '../../core/technicians.service';
import { TechniciansState, TechniciansStore } from '../../core/technicians.store';
import { WCAG_AA, contrastRatio, flatten } from '../dashboard/contrast';
import { TechniciansComponent } from './technicians.component';

const tech = (id: number, name: string, over: Partial<Technician> = {}): Technician => ({
  id, user_id: id + 100, full_name: name, email: `${id}@mantix.io`, employee_code: `EMP-${id}`,
  specialization: id % 2 ? 'Redes' : 'Hardware', is_available: true, is_active: true, hourly_rate: '25.50',
  created_at: '2026-01-01T00:00:00Z', ...over,
});
const state = (technicians: Technician[]): TechniciansState => ({
  technicians,
  workload: Object.fromEntries(technicians.map((t) => [t.id, { technician_id: t.id, full_name: t.full_name, is_available: true, open_tickets: t.id, resolved_in_window: 3 }])),
  hasWorkload: true, windowDays: 30, loading: false, saving: false, error: '', notice: '',
});

describe('TechniciansComponent', () => {
  let fixture: ComponentFixture<TechniciansComponent>;
  const root = () => fixture.nativeElement as HTMLElement;

  let storeRef: jasmine.SpyObj<TechniciansStore>;
  const store = () => storeRef;

  async function create(technicians: Technician[], manage = true): Promise<void> {
    const store = Object.assign(jasmine.createSpyObj('TechniciansStore', ['load', 'clearMessages', 'create', 'update', 'setAvailability']), {
      state$: new BehaviorSubject(state(technicians)),
      saved$: new Subject<Technician>(),
    });
    storeRef = store as unknown as jasmine.SpyObj<TechniciansStore>;
    TestBed.configureTestingModule({
      providers: [
        provideRouter([]),
        { provide: TechniciansStore, useValue: store },
        { provide: LocalProfileService, useValue: { can: () => Promise.resolve(manage) } },
        { provide: ExportService, useValue: { options: () => of({ report: 'technicians', title: 'Técnicos', columns: [], formats: ['pdf', 'xlsx'], max_rows: 10000, warn_rows: 2000, max_range_days: 366 }), count: () => of({ total: 2, max_rows: 10000, warn_rows: 2000, over_limit: false, large: false }), export: () => of() } },
        { provide: QueueService, useValue: { categories: () => of([]) } },
        { provide: TechniciansService, useValue: { list: () => of([]) } },
      ],
    });
    fixture = TestBed.createComponent(TechniciansComponent);
    document.body.appendChild(root());
    fixture.detectChanges();
    await fixture.whenStable();
    fixture.detectChanges();
    (Array.from(root().querySelectorAll('button')).find((b) => b.textContent?.includes('Tabla')) as HTMLButtonElement).click();
    fixture.detectChanges();
  }

  afterEach(() => root().remove());

  describe('card view', () => {
    const cards = () => Array.from(root().querySelectorAll('article')) as HTMLElement[];
    const cardsFirst = async (technicians: Technician[]) => {
      await create(technicians);
      (Array.from(root().querySelectorAll('button')).find((b) => b.textContent?.includes('Tarjetas')) as HTMLButtonElement).click();
      fixture.detectChanges();
    };

    it('shows avatar, name, specialty, availability, tag, e-mail, three stats and the profile button', async () => {
      await cardsFirst([tech(1, 'Suley Suárez', { specialization: 'hardware', hourly_rate: '7000.00', email: 'suley@mantix.io' })]);
      const [card] = cards();
      const text = card.textContent!.replace(/\s+/g, ' ');
      expect(text).toContain('SS');
      expect(text).toContain('Suley Suárez');
      expect(text).toContain('Hardware');
      expect(text.match(/hardware/gi)!.length).toBe(1); // una sola mención: la etiqueta, no también un subtítulo
      expect(text).toContain('suley@mantix.io');
      for (const label of ['Abiertos', 'Resueltos', 'Tarifa por hora']) {
        expect(text).toContain(label);
      }
      expect(text).toContain('$7,000.00');
      expect(text).toContain('Ver ficha técnica');
      expect(card.querySelectorAll('dl').length).toBe(3);
    });

    it('puts Abiertos and Resueltos side by side at 50% each and the rate on its own full row, never cut', async () => {
      await cardsFirst([tech(1, 'Suley Suárez', { hourly_rate: '7000.00' })]);
      const [card] = cards();
      const [open, solved] = Array.from(card.querySelectorAll('.grid-cols-2 > div')) as HTMLElement[];
      expect(Math.abs(open.getBoundingClientRect().width - solved.getBoundingClientRect().width)).toBeLessThan(2);
      expect(Math.abs(open.getBoundingClientRect().top - solved.getBoundingClientRect().top)).toBeLessThan(2);
      const rate = Array.from(card.querySelectorAll('dd')).find((d) => d.textContent!.includes('$7,000.00')) as HTMLElement;
      expect(rate.scrollWidth).toBeLessThanOrEqual(rate.clientWidth); // sin puntos suspensivos
      expect(rate.closest('.grid-cols-2')).toBeNull(); // fila aparte de las dos métricas
      expect(getComputedStyle(rate).textOverflow).not.toBe('ellipsis');
    });

    it('keeps every stat value inside the card (nothing positioned, nothing cut)', async () => {
      await cardsFirst([tech(1, 'Suley Suárez', { hourly_rate: '7000.00' })]);
      const [card] = cards();
      const box = card.getBoundingClientRect();
      for (const dd of Array.from(card.querySelectorAll('dd')) as HTMLElement[]) {
        const r = dd.getBoundingClientRect();
        expect(r.right).withContext(dd.textContent ?? '').toBeLessThanOrEqual(box.right);
        expect(getComputedStyle(dd).marginLeft).toBe('0px');
      }
      expect(card.querySelectorAll('.absolute').length).toBe(0);
    });
  });

  describe('availability toggle', () => {
    const chip = (scope: ParentNode, name: RegExp) => Array.from(scope.querySelectorAll('button')).find((b) => name.test(b.getAttribute('aria-label') ?? '')) as HTMLButtonElement;

    it('table: clicking «No disponible» makes the technician available and clicking «Disponible» does the opposite', async () => {
      await create([tech(1, 'Ana', { is_available: false }), tech(2, 'Luis', { is_available: true })]);
      const row = (name: string) => Array.from(root().querySelectorAll('tbody tr')).find((r) => r.textContent!.includes(name))!;
      chip(row('Ana'), /como disponible/).click();
      expect(store().setAvailability).toHaveBeenCalledWith(jasmine.objectContaining({ id: 1 }), true);
      chip(row('Luis'), /como no disponible/).click();
      expect(store().setAvailability).toHaveBeenCalledWith(jasmine.objectContaining({ id: 2 }), false);
    });

    it('does not open the technician sheet when the chip is pressed', async () => {
      await create([tech(1, 'Ana', { is_available: false })]);
      chip(root().querySelector('tbody tr')!, /como disponible/).click();
      expect(location.search).not.toContain('technician=');
    });

    it('card: the status pill toggles too', async () => {
      await create([tech(1, 'Ana', { is_available: false })]);
      (Array.from(root().querySelectorAll('button')).find((b) => b.textContent?.includes('Tarjetas')) as HTMLButtonElement).click();
      fixture.detectChanges();
      chip(root().querySelector('article')!, /como disponible/).click();
      expect(store().setAvailability).toHaveBeenCalledWith(jasmine.objectContaining({ id: 1 }), true);
    });

    it('is a plain label without permission to manage technicians', async () => {
      await create([tech(1, 'Ana')], false);
      expect(chip(root().querySelector('tbody tr')!, /disponible/)).toBeUndefined();
    });
  });

  it('offers the four requested filters plus the search', async () => {
    await create([tech(1, 'Ana'), tech(2, 'Luis')]);
    for (const label of ['Buscar técnicos', 'Estado de la cuenta', 'Especialidad', 'Disponibilidad', 'Carga de tickets']) {
      expect(root().querySelector(`[aria-label="${label}"]`)).withContext(label).not.toBeNull();
    }
  });

  it('colors the column headers with the palette and keeps their text readable (AA)', async () => {
    await create([tech(1, 'Ana')]);
    const headers = Array.from(root().querySelectorAll('thead th')) as HTMLElement[];
    expect(headers.length).toBe(9);
    const backgrounds = new Set(headers.map((h) => getComputedStyle(h).backgroundColor));
    expect(backgrounds.size).toBeGreaterThanOrEqual(5);
    for (const th of headers) {
      const style = getComputedStyle(th);
      expect(contrastRatio(style.color, flatten(style.backgroundColor, '#ffffff'))).withContext(th.textContent ?? '').toBeGreaterThanOrEqual(WCAG_AA);
    }
  });

  it('centers every column except the long-text ones (technician and specialty)', async () => {
    await create([tech(1, 'Ana')]);
    const cells = Array.from(root().querySelectorAll('tbody tr:first-child td')) as HTMLElement[];
    const align = cells.map((c) => getComputedStyle(c).textAlign);
    expect(align[0]).toBe('left'); // técnico
    expect(align[3]).toBe('left'); // especialidad
    for (const index of [1, 2, 4, 5, 6, 7, 8]) {
      expect(align[index]).withContext(`column ${index}`).toBe('center');
    }
  });

  it('shows the hourly rate and the account state in the table', async () => {
    await create([tech(1, 'Ana'), tech(2, 'Luis', { is_active: false, hourly_rate: null })]);
    const rows = Array.from(root().querySelectorAll('tbody tr')) as HTMLElement[];
    expect(rows[0].textContent).toContain('25.50');
    expect(rows[0].textContent).toContain('Activo');
    expect(rows[1].textContent).toContain('Inactivo');
    expect(rows[1].querySelectorAll('td')[7].textContent).toContain('—');
  });

  it('opens the shared export panel for the technicians report, without a date range', async () => {
    await create([tech(1, 'Ana')]);
    (Array.from(root().querySelectorAll('header button')).find((b) => b.textContent?.includes('Exportar')) as HTMLButtonElement).click();
    fixture.detectChanges();
    const drawer = root().querySelector('app-export-drawer');
    expect(drawer).not.toBeNull();
    expect(root().textContent).toContain('Exportar técnicos');
    expect(root().querySelector('[aria-label="Disponibilidad"][class*="space-y"]')).not.toBeNull();
    expect(root().querySelector('app-export-drawer app-date-range-filter')).toBeNull();
  });
});
