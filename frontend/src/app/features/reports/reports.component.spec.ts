import { Component } from '@angular/core';
import { ComponentFixture, TestBed, fakeAsync, tick } from '@angular/core/testing';
import { BehaviorSubject } from 'rxjs';

import { Catalog, ReportPreview, ReportRun, ReportsOverview } from '../../core/reports.service';
import { ReportsState, ReportsStore } from '../../core/reports.store';
import { WCAG_AA, contrastRatio, flatten } from '../dashboard/contrast';
import { ReportsComponent } from './reports.component';

const catalog: Catalog = {
  reports: [
    {
      key: 'tickets', title: 'Tickets de mantenimiento', description: 'Solicitudes con prioridad.', icon: 'confirmation_number', supports_compare: true,
      filters: [
        { key: 'statuses', label: 'Estado', kind: 'multiselect', options: [{ value: 'closed', label: 'Cerrado' }, { value: 'resolved', label: 'Resuelto' }] },
        { key: 'dates', label: 'Creados entre', kind: 'dates', options: [] },
      ],
    },
    {
      key: 'equipment', title: 'Inventario de equipos', description: 'Cada equipo.', icon: 'desktop_windows', supports_compare: false,
      filters: [{ key: 'statuses', label: 'Estado', kind: 'multiselect', options: [{ value: 'assigned', label: 'Asignado' }] }],
    },
  ],
  max_rows: 10000, max_range_days: 366, formats: ['xlsx', 'pdf', 'csv'],
};
const preview = (overrides: Partial<ReportPreview> = {}): ReportPreview => ({
  report: 'tickets', title: 'Tickets de mantenimiento', columns: [{ key: 'ticket_number', header: 'Ticket' }, { key: 'status', header: 'Estado' }],
  rows: [{ ticket_number: 'T-1', status: 'Cerrado' }, { ticket_number: 'T-2', status: 'En curso' }], total_rows: 40, truncated: false, comparison: null,
  ...overrides,
});
const overview = {
  period: '30d', generated: 12, previous: 8, change_pct: 50, low_sample: false, people: 3,
  most_used: [{ report: 'tickets', title: 'Tickets de mantenimiento', count: 7 }], by_format: { xlsx: 9, pdf: 3 },
  last_export: { report: 'tickets', title: 'Tickets de mantenimiento', export_format: 'pdf', row_count: 120, by: 'Ana', at: '2026-10-14T12:00:00Z' },
} as unknown as ReportsOverview;
const run: ReportRun = { id: 1, report: 'tickets', title: 'Tickets de mantenimiento', export_format: 'xlsx', row_count: 40, filters: {}, by: 'Ana', at: '2026-10-14T12:00:00Z' };

function state(overrides: Partial<ReportsState> = {}): ReportsState {
  return {
    catalog, catalogLoading: false, catalogError: '', selected: 'tickets', preview: preview(), previewLoading: false, previewError: '',
    period: '30d', overview, overviewLoading: false, history: [run], historyTotal: 12, historyPage: 1, exporting: null, ...overrides,
  };
}

@Component({ standalone: true, imports: [ReportsComponent], template: '<div class="tw-reset"><app-reports /></div>' })
class ShellHostComponent {}

describe('ReportsComponent', () => {
  let subject: BehaviorSubject<ReportsState>;
  let store: jasmine.SpyObj<ReportsStore>;
  let fixture: ComponentFixture<ShellHostComponent>;

  const host = () => fixture.nativeElement as HTMLElement;
  const render = (value: ReportsState) => {
    subject.next(value);
    fixture.detectChanges();
  };
  const click = (el: Element | null) => {
    (el as HTMLElement).click();
    fixture.detectChanges();
  };
  const button = (text: string) => Array.from(host().querySelectorAll('button')).find((b) => b.textContent?.includes(text)) ?? null;
  /** El filtro de opciones múltiples es un desplegable: se abre y se marca la opción por su nombre. */
  const menuButton = () => host().querySelector('button[aria-haspopup="listbox"]') as HTMLButtonElement;
  const optionBox = (label: string) =>
    Array.from(host().querySelectorAll('[role="listbox"] label')).find((l) => l.textContent?.trim() === label)?.querySelector('input') as HTMLInputElement;
  const choose = (label: string) => {
    if (!host().querySelector('[role="listbox"]')) {
      click(menuButton());
    }
    click(optionBox(label));
  };
  const isChosen = (label: string) => optionBox(label)?.checked ?? false;
  const chooseFormat = (value: string) => {
    const select = host().querySelector('#rb-format') as HTMLSelectElement;
    select.value = value;
    select.dispatchEvent(new Event('change'));
    fixture.detectChanges();
  };
  const exportButton = () => Array.from(host().querySelectorAll('button')).find((b) => b.textContent?.includes('Exportar')) as HTMLButtonElement;
  const type = (selector: string, value: string) => {
    const input = host().querySelector(selector) as HTMLInputElement;
    input.value = value;
    input.dispatchEvent(new Event('input'));
    fixture.detectChanges();
  };

  function create(initial: ReportsState = state()) {
    subject = new BehaviorSubject(initial);
    store = Object.assign(
      jasmine.createSpyObj('ReportsStore', ['load', 'select', 'setPeriod', 'loadHistory', 'requestPreview', 'export']),
      { state$: subject },
    );
    TestBed.configureTestingModule({ providers: [{ provide: ReportsStore, useValue: store }] });
    fixture = TestBed.createComponent(ShellHostComponent);
    document.body.appendChild(host());
    fixture.detectChanges();
  }

  afterEach(() => host().remove());

  describe('gallery', () => {
    beforeEach(() => create());

    it('shows every report as a tile with its description and marks the selected one', () => {
      const tiles = host().querySelectorAll('nav[aria-label="Galería de reportes"] button');
      expect(tiles.length).toBe(2);
      expect(tiles[0].textContent).toContain('Solicitudes con prioridad.');
      expect(tiles[0].getAttribute('aria-pressed')).toBe('true');
      expect(tiles[1].getAttribute('aria-pressed')).toBe('false');
    });

    it('selects another report from the gallery', () => {
      click(host().querySelectorAll('nav[aria-label="Galería de reportes"] button')[1]);
      expect(store.select).toHaveBeenCalledWith('equipment');
    });

    it('shows skeletons while loading and an error with retry', () => {
      render(state({ catalog: null, catalogLoading: true, selected: null }));
      expect(host().querySelector('[aria-label="Cargando galería"]')).not.toBeNull();
      render(state({ catalog: null, catalogLoading: false, selected: null, catalogError: 'No se pudo cargar la galería de reportes.' }));
      click(button('Reintentar'));
      expect(store.load).toHaveBeenCalled();
    });

    it('shows the hero illustration, decorative and without the placeholder', () => {
      const image = host().querySelector('header img[src$="reportes-hero.webp"]') as HTMLImageElement;
      expect(image.getAttribute('alt')).toBe('');
      expect(image.closest('[aria-hidden="true"]')).not.toBeNull();
      expect(host().querySelector('[data-placeholder="reportes-hero.svg"]')).toBeNull();
    });
  });

  describe('activity', () => {
    beforeEach(() => create());

    it('shows reports generated against the previous period, most used, formats and the last export', () => {
      const text = host().querySelector('[aria-label="Actividad de reportes"]')!.textContent!;
      expect(text).toContain('12');
      expect(text).toContain('▲ 50%');
      expect(text).toContain('antes: 8');
      expect(text).toContain('3 personas');
      expect(text).toContain('Tickets de mantenimiento');
      expect(text).toContain('9 Excel');
      expect(text).toContain('PDF · 120 filas · Ana');
    });

    it('flags a few reports and says so when there is no activity or it is unavailable', () => {
      render(state({ overview: { ...overview, low_sample: true } }));
      expect(host().querySelector('[aria-label="Actividad de reportes"]')!.textContent).toContain('pocos datos');
      render(state({ overview: { ...overview, generated: 0, previous: 0, change_pct: null, most_used: [], by_format: {}, last_export: null } as unknown as ReportsOverview }));
      expect(host().querySelector('[aria-label="Actividad de reportes"]')!.textContent).toContain('Ninguna todavía.');
      render(state({ overview: null }));
      expect(host().textContent).toContain('La actividad de reportes no está disponible');
    });

    it('changes the activity period', () => {
      click(button('12 meses'));
      expect(store.setPeriod).toHaveBeenCalledWith('12m');
    });
  });

  describe('builder', () => {
    beforeEach(() => create());

    it('shows only the filters of the selected report, as drop-downs that start on «Todos»', () => {
      expect(host().querySelector('[aria-label="Constructor de filtros"]')!.textContent).toContain('Creados entre');
      expect(menuButton().textContent).toContain('Todos');
      click(menuButton());
      expect(optionBox('Cerrado')).toBeDefined();
      render(state({ selected: 'equipment' }));
      expect(host().querySelector('[aria-label="Constructor de filtros"]')!.textContent).not.toContain('Creados entre');
      expect(host().textContent).not.toContain('Comparar con el periodo anterior');
    });

    it('asks for the preview as soon as the report is shown, and again (debounced) when a filter changes', fakeAsync(() => {
      expect(store.requestPreview).toHaveBeenCalledTimes(1);
      choose('Cerrado');
      choose('Resuelto');
      expect(store.requestPreview).toHaveBeenCalledTimes(1);
      tick(350);
      expect(store.requestPreview).toHaveBeenCalledTimes(2);
      const [values, compare] = store.requestPreview.calls.mostRecent().args;
      expect(values.statuses).toEqual(['closed', 'resolved']);
      expect(compare).toBeFalse();
      expect(isChosen('Cerrado')).toBeTrue();
      expect(menuButton().textContent).toContain('2 seleccionados');
      choose('Cerrado');
      tick(350);
      expect(menuButton().textContent).toContain('Resuelto');
      expect(store.requestPreview.calls.mostRecent().args[0].statuses).toEqual(['resolved']);
    }));

    it('explains an inverted range and does not ask for a preview', fakeAsync(() => {
      store.requestPreview.calls.reset();
      type('#rb-from', '2026-09-10');
      type('#rb-to', '2026-09-01');
      tick(350);
      fixture.detectChanges();
      expect(host().querySelector('#rb-range-err')!.textContent).toContain('La fecha final no puede ser anterior a la inicial.');
      expect(store.requestPreview).not.toHaveBeenCalled();
      expect(host().textContent).toContain('Corrige los filtros marcados para ver la vista previa.');
      expect(exportButton().disabled).toBeTrue();
    }));

    it('rejects a range longer than 366 days and accepts exactly 366', fakeAsync(() => {
      type('#rb-from', '2026-01-01');
      type('#rb-to', '2027-01-02');
      tick(350);
      expect(host().querySelector('#rb-range-err')!.textContent).toContain('El rango no puede superar 366 días.');
      store.requestPreview.calls.reset();
      type('#rb-from', '2028-01-01');
      type('#rb-to', '2028-12-31');
      tick(350);
      expect(host().querySelector('#rb-range-err')!.textContent!.trim()).toBe('');
      expect(store.requestPreview).toHaveBeenCalled();
    }));

    it('only compares when both dates are set', fakeAsync(() => {
      const check = host().querySelector('input[type="checkbox"]') as HTMLInputElement;
      expect(host().textContent).toContain('Elige fecha inicial y final para comparar.');
      check.click();
      type('#rb-from', '2026-09-01');
      tick(350);
      expect(store.requestPreview.calls.mostRecent().args[1]).toBeFalse(); // falta la fecha final
      type('#rb-to', '2026-09-30');
      tick(350);
      expect(store.requestPreview.calls.mostRecent().args[1]).toBeTrue();
      expect(host().textContent).toContain('Mismo número de días justo antes del rango.');
    }));

    it('clears the filters with «Limpiar filtros»', fakeAsync(() => {
      choose('Cerrado');
      tick(350);
      expect(menuButton().textContent).toContain('Cerrado');
      click(button('Limpiar filtros'));
      expect(menuButton().textContent).toContain('Todos');
    }));

    it('closes the drop-down with Escape or a click outside', () => {
      click(menuButton());
      expect(host().querySelector('[role="listbox"]')).not.toBeNull();
      document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
      fixture.detectChanges();
      expect(host().querySelector('[role="listbox"]')).toBeNull();
      click(menuButton());
      click(host().querySelector('header h1'));
      expect(host().querySelector('[role="listbox"]')).toBeNull();
    });
  });

  describe('export', () => {
    beforeEach(() => create());

    it('exports in the chosen format with the current filters', fakeAsync(() => {
      choose('Cerrado');
      tick(350);
      expect(exportButton().textContent).toContain('Exportar Excel');
      click(exportButton());
      expect(store.export).toHaveBeenCalledWith('xlsx', jasmine.objectContaining({ statuses: ['closed'] }));
      chooseFormat('pdf');
      expect(exportButton().textContent).toContain('Exportar PDF');
      click(exportButton());
      expect(store.export.calls.mostRecent().args[0]).toBe('pdf');
    }));

    it('is disabled with a reason when there is nothing to export', () => {
      render(state({ preview: preview({ rows: [], total_rows: 0 }) }));
      expect(exportButton().disabled).toBeTrue();
      expect(host().textContent).toContain('No hay filas que exportar con estos filtros.');
    });

    it('is disabled when the result is above the row limit', () => {
      render(state({ preview: preview({ total_rows: 10000, truncated: true }) }));
      expect(exportButton().disabled).toBeTrue();
      expect(host().textContent).toContain('Acota los filtros para poder exportar.');
      expect(host().textContent).toContain('10000+ filas');
    });

    it('shows progress and blocks a second export while generating', () => {
      render(state({ exporting: 'pdf' }));
      expect(exportButton()).toBeUndefined();
      const generating = Array.from(host().querySelectorAll('button')).find((b) => b.textContent?.includes('Generando…')) as HTMLButtonElement;
      expect(generating.disabled).toBeTrue();
    });
  });

  describe('preview', () => {
    beforeEach(() => create());

    it('shows the first rows with the total', () => {
      const table = host().querySelector('section[aria-label="Vista previa"] table')!;
      expect(table.querySelectorAll('tbody tr').length).toBe(2);
      expect(table.textContent).toContain('En curso');
      expect(host().querySelector('section[aria-label="Vista previa"]')!.textContent).toContain('Mostrando 2 de 40 filas.');
    });

    it('shows the comparison with the previous period', () => {
      render(state({ preview: preview({ comparison: { current_total: 6, previous_total: 4, change_pct: 50, previous_from: '2026-08-01T00:00:00Z', previous_to: '2026-08-31T00:00:00Z' } }) }));
      const block = host().querySelector('[aria-label="Comparativo con el periodo anterior"]')!.textContent!;
      expect(block).toContain('Este periodo');
      expect(block).toContain('6');
      expect(block).toContain('▲ 50%');
    });

    it('shows a dash instead of a percentage when the previous period has no rows', () => {
      render(state({ preview: preview({ comparison: { current_total: 3, previous_total: 0, change_pct: null, previous_from: '2026-08-01T00:00:00Z', previous_to: '2026-08-31T00:00:00Z' } }) }));
      expect(host().querySelector('[aria-label="Comparativo con el periodo anterior"]')!.textContent).toContain('—');
    });

    it('shows loading, error and empty states with the illustration', () => {
      render(state({ preview: null, previewLoading: true }));
      expect(host().querySelector('[aria-label="Generando vista previa"]')).not.toBeNull();
      render(state({ preview: null, previewError: 'No se pudo generar la vista previa.' }));
      expect(host().querySelector('section[aria-label="Vista previa"] [role="alert"]')!.textContent).toContain('No se pudo generar');
      render(state({ preview: preview({ rows: [], total_rows: 0 }) }));
      expect(host().textContent).toContain('Ninguna fila coincide con estos filtros');
      expect(host().querySelector('img[src$="cola-vacia.svg"]')).not.toBeNull();
    });
  });

  describe('layout', () => {
    beforeEach(() => create());
    const wide = (columns: number, text = 'Valor largo de la celda con varias palabras y un identificador-sin-espacios-muy-largo-123456789') => {
      const cols = Array.from({ length: columns }, (_, i) => ({ key: `c${i}`, header: `Columna ${i + 1}` }));
      const row = Object.fromEntries(cols.map((c) => [c.key, text]));
      return preview({ columns: cols, rows: [row, row], total_rows: 2 });
    };

    it('shows the report gallery as a grid of equal tiles, not a tall side column', () => {
      const nav = host().querySelector('nav[aria-label="Galería de reportes"]')!;
      expect(getComputedStyle(nav).display).toBe('grid');
      const [a, b] = Array.from(nav.querySelectorAll('button')).map((el) => el.getBoundingClientRect());
      expect(Math.abs(a.height - b.height)).toBeLessThan(1);
      expect(Math.abs(a.width - b.width)).toBeLessThan(1);
    });

    it('has the filters panel (with the format and «Limpiar filtros») beside the report panel that holds the preview and the export', () => {
      const filters = host().querySelector('section[aria-label="Constructor de filtros"]') as HTMLElement;
      const panel = host().querySelector('section[aria-label="Reporte y exportaciones"]') as HTMLElement;
      expect(filters.textContent).toContain('Selecciona los criterios para tu reporte.');
      expect(filters.querySelector('#rb-format')).not.toBeNull();
      expect(filters.textContent).toContain('Limpiar filtros');
      expect(panel.contains(host().querySelector('section[aria-label="Vista previa"]'))).toBeTrue();
      expect(panel.textContent).toContain('Vista previa');
      expect(panel.contains(exportButton())).toBeTrue();
      expect(filters.compareDocumentPosition(panel) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    });

    it('asks for the preview again with the «Vista previa» button', () => {
      store.requestPreview.calls.reset();
      click(button('Vista previa'));
      expect(store.requestPreview).toHaveBeenCalledTimes(1);
    });

    it('draws the four activity cards at the same size', () => {
      const cards = Array.from(host().querySelectorAll('[aria-label="Actividad de reportes"] dl > div')).map((el) => el.getBoundingClientRect());
      expect(cards.length).toBe(4);
      expect(Math.max(...cards.map((c) => c.width)) - Math.min(...cards.map((c) => c.width))).toBeLessThan(1);
    });

    it('shows the whole table with no horizontal scroll, wrapping long cells', () => {
      render(state({ preview: wide(7) }));
      const section = host().querySelector('section[aria-label="Vista previa"]') as HTMLElement;
      expect(section.querySelector('.overflow-x-auto')).toBeNull();
      expect(section.innerHTML).not.toContain('min-w-[');
      const table = section.querySelector('table') as HTMLElement;
      expect(table.scrollWidth).toBeLessThanOrEqual(section.clientWidth);
      expect(section.scrollWidth).toBeLessThanOrEqual(section.clientWidth + 1);
      const cell = table.querySelector('tbody td') as HTMLElement;
      expect(getComputedStyle(cell).whiteSpace).not.toBe('nowrap');
      expect(getComputedStyle(cell).textOverflow).not.toBe('ellipsis');
      expect(table.querySelector('tbody button[aria-expanded]')).toBeNull(); // 7 columns: no detail needed
    });

    it('keeps the essential columns and moves the rest to an expandable detail per row', () => {
      render(state({ preview: wide(12, 'dato') }));
      const section = host().querySelector('section[aria-label="Vista previa"]') as HTMLElement;
      expect(Array.from(section.querySelectorAll('thead th')).filter((th) => th.textContent!.startsWith('Columna')).length).toBe(7);
      expect(section.textContent).not.toContain('Columna 8');
      const toggle = section.querySelector('tbody button[aria-expanded="false"]') as HTMLButtonElement;
      expect(toggle.getAttribute('aria-label')).toBe('Ver el detalle de la fila 1');
      click(toggle);
      expect(toggle.getAttribute('aria-expanded')).toBe('true');
      const detail = section.querySelector('tbody dl')!;
      expect(detail.textContent).toContain('Columna 8');
      expect(detail.textContent).toContain('Columna 12');
      expect(detail.querySelectorAll('dt').length).toBe(5);
      click(toggle);
      expect(section.querySelector('tbody dl')).toBeNull();
      expect(section.scrollWidth).toBeLessThanOrEqual(section.clientWidth + 1);
    });
  });

  describe('history', () => {
    beforeEach(() => create());

    it('lists the latest exports inside the report panel, and «Ver todas» opens the paged history', () => {
      const table = host().querySelector('section[aria-label="Exportaciones recientes"]')!;
      expect(host().querySelector('section[aria-label="Reporte y exportaciones"]')!.contains(table)).toBeTrue();
      expect(table.textContent).toContain('Tickets de mantenimiento');
      expect(table.textContent).toContain('Excel');
      expect(table.textContent).toContain('12 exportaciones');
      expect(table.textContent).not.toContain('Exportaciones 1–8 de 12');
      click(Array.from(table.querySelectorAll('button')).find((b) => b.textContent?.includes('Ver todas'))!);
      expect(table.textContent).toContain('Exportaciones 1–8 de 12');
      click(Array.from(table.querySelectorAll('button')).find((b) => b.textContent?.includes('Siguiente'))!);
      expect(store.loadHistory).toHaveBeenCalledWith(2);
    });

    it('shows at most five recent rows before «Ver todas»', () => {
      const many = Array.from({ length: 8 }, (_, i) => ({ ...run, id: i + 1 }));
      render(state({ history: many, historyTotal: 8 }));
      const rows = () => host().querySelectorAll('section[aria-label="Exportaciones recientes"] tbody tr').length;
      expect(rows()).toBe(5);
      click(button('Ver todas'));
      expect(rows()).toBe(8);
      click(button('Ver menos'));
      expect(rows()).toBe(5);
    });

    it('says so when nothing has been exported', () => {
      render(state({ history: [], historyTotal: 0 }));
      expect(host().textContent).toContain('Todavía no se ha exportado ningún reporte.');
    });
  });

  describe('contrast inside the .tw-reset shell (AA, 4.5:1)', () => {
    beforeEach(() => create());

    it('keeps the export button, the format toggle and the filter chips legible', fakeAsync(() => {
      choose('Cerrado');
      tick(350);
      const ratio = (el: Element, backdrop = '#ffffff') => {
        const style = getComputedStyle(el);
        const background = style.backgroundColor === 'rgba(0, 0, 0, 0)' ? backdrop : flatten(style.backgroundColor, backdrop);
        return contrastRatio(flatten(style.color), background);
      };
      expect(ratio(exportButton())).toBeGreaterThanOrEqual(WCAG_AA);
      for (const el of Array.from(host().querySelectorAll('[role="group"] button, button[aria-haspopup="listbox"]'))) {
        expect(ratio(el)).withContext(el.textContent ?? '').toBeGreaterThanOrEqual(WCAG_AA);
      }
    }));
  });
});
