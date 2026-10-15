import { HttpErrorResponse } from '@angular/common/http';
import { Component, signal } from '@angular/core';
import { ComponentFixture, TestBed, fakeAsync, flush, tick } from '@angular/core/testing';
import { Subject, of, throwError } from 'rxjs';

import { ExportCount, ExportOptions, ExportService } from '../../core/export.service';
import { QueueService } from '../../core/queue.service';
import { Technician, TechniciansService } from '../../core/technicians.service';
import { ToastService } from '../../core/toast.service';
import { WCAG_AA, contrastRatio, flatten } from '../dashboard/contrast';
import { ChoiceOption, ExportDrawerComponent } from './export-drawer.component';
import { EMPTY_EXPORT_FILTERS, ExportFilterValues } from './export-model';

const options: ExportOptions = {
  report: 'tickets', title: 'Reporte de tickets', formats: ['pdf', 'xlsx'], max_rows: 10_000, warn_rows: 2_000, max_range_days: 366,
  columns: [
    { key: 'ticket_number', label: 'Ticket', kind: 'text', default_pdf: true, default_xlsx: true },
    { key: 'serial', label: 'Serial', kind: 'text', default_pdf: false, default_xlsx: true },
    { key: 'total_cost', label: 'Costo total', kind: 'money', default_pdf: true, default_xlsx: true },
  ],
};
const count = (total: number, extra: Partial<ExportCount> = {}): ExportCount => ({
  total, max_rows: 10_000, warn_rows: 2_000, over_limit: total > 10_000, large: total > 2_000 && total <= 10_000, ...extra,
});
const statusOptions: ChoiceOption[] = [{ value: 'resolved', label: 'Resuelto' }, { value: 'closed', label: 'Cerrado' }];
const priorityOptions: ChoiceOption[] = [{ value: 'high', label: 'Alta' }];

@Component({
  standalone: true,
  imports: [ExportDrawerComponent],
  template: `<div class="tw-reset">@if (open()) {
    <app-export-drawer report="tickets" title="tickets" [initial]="initial()" [filterKinds]="['statuses', 'priorities', 'technicians']"
      [statusOptions]="statusOptions" [priorityOptions]="priorityOptions" (closed)="closedCount = closedCount + 1; open.set(false)" />
  }</div>`,
})
class HostComponent {
  readonly open = signal(true);
  readonly initial = signal<ExportFilterValues | null>(null);
  readonly statusOptions = statusOptions;
  readonly priorityOptions = priorityOptions;
  closedCount = 0;
}

describe('ExportDrawerComponent', () => {
  let api: jasmine.SpyObj<ExportService>;
  let toasts: ToastService;
  let fixture: ComponentFixture<HostComponent>;

  const host = () => fixture.nativeElement as HTMLElement;
  const settle = () => {
    tick(350);
    fixture.detectChanges();
  };
  const button = (text: string) => Array.from(host().querySelectorAll('button')).find((b) => b.textContent?.trim().includes(text)) as HTMLButtonElement | undefined;
  const click = (el: Element | undefined | null) => {
    (el as HTMLElement).click();
    fixture.detectChanges();
  };
  const exportButton = () => Array.from(host().querySelectorAll('footer button')).find((b) => /Exportar|Generando|Reintentar/.test(b.textContent ?? '')) as HTMLButtonElement;
  const type = (selector: string, value: string) => {
    const input = host().querySelector(selector) as HTMLInputElement;
    input.value = value;
    input.dispatchEvent(new Event('change'));
    fixture.detectChanges();
  };
  const status = () => host().querySelector('footer [role="status"]')!.textContent!.trim();

  function create(initial: ExportFilterValues | null = null): void {
    TestBed.configureTestingModule({
      providers: [
        { provide: ExportService, useValue: api },
        { provide: TechniciansService, useValue: { list: () => of([{ id: 4, full_name: 'Luis Gómez' } as Technician]) } },
        { provide: QueueService, useValue: { categories: () => of([]) } },
      ],
    });
    toasts = TestBed.inject(ToastService);
    fixture = TestBed.createComponent(HostComponent);
    fixture.componentInstance.initial.set(initial);
    document.body.appendChild(host());
    fixture.detectChanges();
  }

  beforeEach(() => {
    api = jasmine.createSpyObj('ExportService', ['options', 'count', 'export']);
    api.options.and.returnValue(of(options));
    api.count.and.returnValue(of(count(12)));
    api.export.and.returnValue(of({ blob: new Blob(['x']), filename: 'mantix_tickets_2026-10-14.pdf' }));
    spyOn(URL, 'createObjectURL').and.returnValue('blob:x');
    spyOn(URL, 'revokeObjectURL');
    spyOn(HTMLAnchorElement.prototype, 'click');
  });

  afterEach(() => host().remove());

  describe('layout and the live counter', () => {
    it('offers PDF and Excel as two cards, with PDF chosen', fakeAsync(() => {
      create();
      settle();
      const cards = host().querySelectorAll('[role="radio"]');
      expect(cards.length).toBe(2);
      expect(cards[0].textContent).toContain('PDF');
      expect(cards[1].textContent).toContain('Excel');
      expect(cards[0].getAttribute('aria-checked')).toBe('true');
      expect(host().querySelector('[role="dialog"]')!.getAttribute('aria-modal')).toBe('true');
      flush();
    }));

    it('says how many records will be exported, with the screen filters already applied', fakeAsync(() => {
      create({ ...EMPTY_EXPORT_FILTERS, statuses: ['resolved'], priorities: ['high'], dateFrom: '2026-09-01', dateTo: '2026-09-30' });
      settle();
      expect(api.count).toHaveBeenCalledTimes(1);
      const [report, filters] = api.count.calls.mostRecent().args;
      expect(report).toBe('tickets');
      expect(filters.statuses).toEqual(['resolved']);
      expect(filters.priorities).toEqual(['high']);
      expect(filters.date_from).toBeDefined();
      expect(status()).toBe('Se exportarán 12 registros.');
      expect(host().querySelector('[aria-label="Estado"] [aria-pressed="true"]')!.textContent).toContain('Resuelto');
      expect(button('Personalizado')!.getAttribute('aria-pressed')).toBe('true');
      flush();
    }));

    it('recounts (debounced) when a filter changes and ignores the stale answer', fakeAsync(() => {
      create();
      settle();
      const slow = new Subject<ExportCount>();
      api.count.and.returnValue(slow);
      click(host().querySelector('[aria-label="Estado"] button'));
      click(host().querySelectorAll('[aria-label="Estado"] button')[1]);
      expect(api.count).toHaveBeenCalledTimes(1); // still waiting out the debounce
      tick(350);
      expect(api.count).toHaveBeenCalledTimes(2);
      expect(api.count.calls.mostRecent().args[1].statuses).toEqual(['resolved', 'closed']);
      expect(status()).toBe('Contando registros…');
      slow.next(count(3));
      fixture.detectChanges();
      expect(status()).toBe('Se exportarán 3 registros.');
      flush();
    }));

    it('blocks the export and explains it when nothing matches', fakeAsync(() => {
      api.count.and.returnValue(of(count(0)));
      create();
      settle();
      expect(status()).toContain('Ningún registro coincide');
      expect(exportButton().disabled).toBeTrue();
      flush();
    }));

    it('blocks the export above the row limit and only warns about a large one', fakeAsync(() => {
      api.count.and.returnValue(of(count(12_500)));
      create();
      settle();
      expect(status()).toContain('el máximo es 10.000');
      expect(exportButton().disabled).toBeTrue();
      api.count.and.returnValue(of(count(2_500)));
      click(host().querySelectorAll('[aria-label="Prioridad"] button')[0]);
      settle();
      expect(status()).toContain('puede tardar');
      expect(exportButton().disabled).toBeFalse();
      flush();
    }));

    it('says when the count fails and keeps the export disabled', fakeAsync(() => {
      api.count.and.returnValue(throwError(() => new HttpErrorResponse({ status: 500 })));
      create();
      settle();
      expect(status()).toContain('No se pudo contar');
      expect(exportButton().disabled).toBeTrue();
      flush();
    }));
  });

  describe('dates', () => {
    it('applies the shortcuts', fakeAsync(() => {
      create();
      settle();
      click(button('Hoy'));
      const from = host().querySelector('input[id$="-from"]') as HTMLInputElement;
      const to = host().querySelector('input[id$="-to"]') as HTMLInputElement;
      expect(from.value).toBe(to.value);
      expect(from.value).toBe(host().querySelector('input[id$="-from"]')!.getAttribute('max')!);
      click(button('Todo'));
      expect((host().querySelector('input[id$="-from"]') as HTMLInputElement).value).toBe('');
      click(button('30 días'));
      expect((host().querySelector('input[id$="-from"]') as HTMLInputElement).value).not.toBe('');
      expect(button('30 días')!.getAttribute('aria-pressed')).toBe('true');
      type('input[id$="-from"]', '2026-01-01');
      expect(button('Personalizado')!.getAttribute('aria-pressed')).toBe('true');
      flush();
    }));

    it('explains an inverted or oversized range and does not ask the server', fakeAsync(() => {
      create();
      settle();
      api.count.calls.reset();
      type('input[id$="-from"]', '2026-09-10');
      type('input[id$="-to"]', '2026-09-01');
      tick(350);
      fixture.detectChanges();
      expect(host().querySelector('fieldset [role="alert"]')!.textContent).toContain('La fecha final no puede ser anterior a la inicial.');
      expect(api.count).not.toHaveBeenCalled();
      expect(exportButton().disabled).toBeTrue();
      expect(status()).toContain('Corrige el rango de fechas');
      type('input[id$="-from"]', '2025-01-01');
      type('input[id$="-to"]', '2026-06-01');
      expect(host().querySelector('fieldset [role="alert"]')!.textContent).toContain('366 días');
      flush();
    }));

    it('rejects a start date in the future', fakeAsync(() => {
      create();
      settle();
      type('input[id$="-from"]', '2999-01-01');
      expect(host().querySelector('fieldset [role="alert"]')!.textContent).toContain('no puede ser futura');
      flush();
    }));
  });

  describe('content', () => {
    it('lets Excel pick columns and needs at least one', fakeAsync(() => {
      create();
      settle();
      click(host().querySelectorAll('[role="radio"]')[1]);
      expect(host().querySelectorAll('[aria-label="Columnas"] input[type="checkbox"]').length).toBe(3);
      expect(button('Exportar Excel')).toBeDefined();
      click(button('Ninguna'));
      expect(host().textContent).toContain('Elige al menos una columna.');
      expect(exportButton().disabled).toBeTrue();
      click(host().querySelectorAll('[aria-label="Columnas"] input')[2]);
      expect(exportButton().disabled).toBeFalse();
      click(exportButton());
      expect(api.export.calls.mostRecent().args[1]).toBe('xlsx');
      expect(api.export.calls.mostRecent().args[2].columns).toEqual(['total_cost']);
      flush();
    }));

    it('sends the PDF with the default columns, the summary and the charts', fakeAsync(() => {
      create();
      settle();
      click(exportButton());
      const request = api.export.calls.mostRecent().args[2];
      expect(request.columns).toBeUndefined();
      expect(request.include_summary && request.include_charts).toBeTrue();
      flush();
    }));

    it('turns the charts off with the summary', fakeAsync(() => {
      create();
      settle();
      const [summary, charts] = Array.from(host().querySelectorAll('[aria-label="Contenido del PDF"] input')) as HTMLInputElement[];
      summary.click();
      fixture.detectChanges();
      expect(charts.disabled).toBeTrue();
      click(exportButton());
      const request = api.export.calls.mostRecent().args[2];
      expect(request.include_summary).toBeFalse();
      expect(request.include_charts).toBeFalse();
      flush();
    }));
  });

  describe('generating', () => {
    it('shows progress, ignores a second click and downloads when done', fakeAsync(() => {
      const gate = new Subject<{ blob: Blob; filename: string }>();
      api.export.and.returnValue(gate);
      create();
      settle();
      click(exportButton());
      expect(exportButton().textContent).toContain('Generando…');
      expect(exportButton().disabled).toBeTrue();
      (exportButton() as HTMLElement).click();
      expect(api.export).toHaveBeenCalledTimes(1);
      host().querySelector<HTMLElement>('[aria-label="Cerrar panel de exportación"]')!.click();
      expect(fixture.componentInstance.closedCount).toBe(0); // no closing mid-download
      gate.next({ blob: new Blob(['x']), filename: 'mantix_tickets_2026-10-14.pdf' });
      gate.complete();
      fixture.detectChanges();
      expect(HTMLAnchorElement.prototype.click).toHaveBeenCalled();
      expect(host().textContent).toContain('Archivo generado');
      expect(host().textContent).toContain('mantix_tickets_2026-10-14.pdf');
      expect(toasts.toasts()[0].message).toBe('Archivo generado: mantix_tickets_2026-10-14.pdf');
      flush();
    }));

    it('can download again and close after success', fakeAsync(() => {
      create();
      settle();
      click(exportButton());
      (HTMLAnchorElement.prototype.click as jasmine.Spy).calls.reset();
      click(button('Descargar de nuevo'));
      expect(HTMLAnchorElement.prototype.click).toHaveBeenCalledTimes(1);
      click(button('Cerrar'));
      expect(fixture.componentInstance.closedCount).toBe(1);
      flush();
    }));

    it('shows a readable error and retries', async () => {
      const body = new Blob([JSON.stringify({ code: 'unprocessable', detail: 'no records match the filters; nothing to export' })], { type: 'application/json' });
      api.export.and.returnValue(throwError(() => new HttpErrorResponse({ status: 422, error: body })));
      create();
      await new Promise((resolve) => setTimeout(resolve, 380)); // the Blob body is read for real, so no fake clock here
      fixture.detectChanges();
      click(exportButton());
      await new Promise((resolve) => setTimeout(resolve, 60));
      fixture.detectChanges();
      expect(host().querySelector('footer [role="alert"]')!.textContent).toContain('No hay registros que coincidan con los filtros');
      expect(exportButton().textContent).toContain('Reintentar');
      api.export.and.returnValue(of({ blob: new Blob(['x']), filename: 'a.pdf' }));
      click(exportButton());
      expect(api.export).toHaveBeenCalledTimes(2);
      expect(host().textContent).toContain('Archivo generado');
    });
  });

  describe('closing and accessibility', () => {
    it('closes with Escape and with the close button', fakeAsync(() => {
      create();
      settle();
      host().querySelector('app-export-drawer')!.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
      fixture.detectChanges();
      expect(fixture.componentInstance.closedCount).toBe(1);
      flush();
    }));

    it('keeps the export button legible inside .tw-reset (AA, 4.5:1)', fakeAsync(() => {
      create();
      settle();
      const el = exportButton();
      const style = getComputedStyle(el);
      const background = style.backgroundColor === 'rgba(0, 0, 0, 0)' ? '#ffffff' : flatten(style.backgroundColor, '#ffffff');
      expect(contrastRatio(flatten(style.color), background)).toBeGreaterThanOrEqual(WCAG_AA);
      flush();
    }));
  });
});
