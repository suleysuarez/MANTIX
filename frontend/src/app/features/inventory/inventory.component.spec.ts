import { Component } from '@angular/core';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { BehaviorSubject, of } from 'rxjs';

import { InventoryItem, InventoryOverview, Movement } from '../../core/inventory.service';
import { EMPTY_FILTERS, InventoryState, InventoryStore } from '../../core/inventory.store';
import { LocalProfileService } from '../../core/local-profile.service';
import { WCAG_AA, contrastRatio, flatten } from '../dashboard/contrast';
import { InventoryComponent } from './inventory.component';

const item = (overrides: Partial<InventoryItem> = {}): InventoryItem => ({
  id: 1, sku: 'SSD-512', name: 'SSD 512 GB', description: null, category: 'spare_part', unit: 'unidad', unit_cost: '64.90',
  stock: 12, min_stock: 5, max_stock: 40, location: 'Bodega A', supplier: null, is_active: true, status: 'ok',
  stock_value: '778.80', level_pct: 30, last_movement_at: null, created_at: '', updated_at: '', ...overrides,
});

const overview = {
  period: '30d',
  stock_value: { total: '1500.00', previous: '1200.00', change_pct: 25, items: 8 },
  low_stock: 2, out_of_stock: 1,
  consumption: { units: 9, value: '90.00', previous_units: 6, change_pct: 50, movements: 3, low_sample: true },
  rotation: { value: 0.38, previous: null, change_pct: null },
  monthly_consumption: [{ month: '2026-09-01T00:00:00Z', units: 4 }, { month: '2026-10-01T00:00:00Z', units: 5 }],
  stale_count: 1, stale_items: [{ item_id: 9, sku: 'OLD-1', name: 'Cable viejo', stock: 9, last_movement_at: null }],
  most_used: [{ item_id: 1, sku: 'SSD-512', name: 'SSD 512 GB', units: 7 }],
  reorder: [
    { item_id: 2, sku: 'RAM-8', name: 'RAM 8 GB', stock: 0, min_stock: 4, suggested_order: 20 },
    { item_id: 3, sku: 'CAB-1', name: 'Cable HDMI', stock: 2, min_stock: 5, suggested_order: 8 },
  ],
} as unknown as InventoryOverview;

function state(overrides: Partial<InventoryState> = {}): InventoryState {
  return {
    view: 'grid', filters: EMPTY_FILTERS, items: [item(), item({ id: 2, sku: 'RAM-8', name: 'RAM 8 GB', stock: 0, status: 'out', level_pct: 0 })],
    total: 30, page: 1, loading: false, error: '', period: '30d', overview, overviewLoading: false, selectedId: null,
    item: null, movements: [], movementsTotal: 0, detailLoading: false, detailError: '', busy: false, ...overrides,
  };
}

@Component({ standalone: true, imports: [InventoryComponent], template: '<div class="tw-reset"><app-inventory /></div>' })
class ShellHostComponent {}

describe('InventoryComponent', () => {
  let subject: BehaviorSubject<InventoryState>;
  let store: jasmine.SpyObj<InventoryStore>;
  let fixture: ComponentFixture<ShellHostComponent>;

  const host = () => fixture.nativeElement as HTMLElement;
  const render = (value: InventoryState) => {
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
  const message = (id: string) => host().querySelector(`#${id}`)!.textContent!.trim();

  async function create(permissions: string[] = ['inventory.manage', 'inventory.consume']) {
    subject = new BehaviorSubject(state());
    store = Object.assign(
      jasmine.createSpyObj('InventoryStore', ['load', 'setView', 'setFilters', 'clearFilters', 'setPage', 'setPeriod', 'select', 'create', 'update', 'remove', 'move', 'importFile', 'exportAll']),
      { state$: subject },
    );
    for (const method of ['create', 'update', 'remove', 'move'] as const) {
      (store[method] as jasmine.Spy).and.returnValue(of({ ok: true, fieldErrors: {} }));
    }
    TestBed.configureTestingModule({
      providers: [
        { provide: InventoryStore, useValue: store },
        { provide: LocalProfileService, useValue: { can: (p: string) => Promise.resolve(permissions.includes(p)) } },
      ],
    });
    fixture = TestBed.createComponent(ShellHostComponent);
    document.body.appendChild(host());
    fixture.detectChanges();
    await fixture.whenStable();
    fixture.detectChanges();
  }

  afterEach(() => host().remove());

  describe('cards', () => {
    beforeEach(() => create());

    it('shows each item with its stock level bar, minimum marker and status chip', () => {
      const cards = host().querySelectorAll('section[aria-label="Ítems"] li');
      expect(cards.length).toBe(2);
      expect(cards[0].textContent).toContain('SSD 512 GB');
      expect(cards[0].textContent).toContain('En stock');
      expect(cards[0].querySelector('[role="img"]')!.getAttribute('aria-label')).toContain('mínimo 5');
      expect(cards[0].querySelector('.absolute.bg-on-surface')).not.toBeNull(); // marca del mínimo
      expect(cards[1].textContent).toContain('Agotado');
    });

    it('opens the detail from a card and offers consume (disabled at zero stock) and entry', () => {
      click(host().querySelector('button[aria-label="Abrir SSD 512 GB"]'));
      expect(store.select).toHaveBeenCalledWith(1);
      const consume = Array.from(host().querySelectorAll('button')).filter((b) => b.textContent?.trim() === 'Consumir');
      expect(consume.length).toBe(2);
      expect(consume[0].disabled).toBeFalse();
      expect(consume[1].disabled).toBeTrue();
      expect(button('Entrada')).not.toBeNull();
    });

    it('lists replenishment alerts, emptiest first, and opens the item from one', () => {
      const strip = host().querySelector('[aria-label="Alertas de reposición"]')!;
      expect(strip.textContent).toContain('Reponer (2)');
      expect(strip.textContent).toContain('pedir 20');
      click(strip.querySelector('button'));
      expect(store.select).toHaveBeenCalledWith(2);
    });

    it('switches to the dense table and sorts by column on the server', () => {
      click(host().querySelector('button[aria-label="Tabla"]'));
      expect(store.setView).toHaveBeenCalledWith('table');
      render(state({ view: 'table' }));
      expect(host().querySelectorAll('tbody tr').length).toBe(2);
      click(button('Stock'));
      expect(store.setFilters).toHaveBeenCalledWith({ sort: 'stock' });
      render(state({ view: 'table', filters: { ...EMPTY_FILTERS, sort: '-stock' } }));
      expect(host().querySelector('th[aria-sort="descending"]')).not.toBeNull();
    });

    it('paginates on the server and shows the range', () => {
      expect(host().querySelector('nav[aria-label="Paginación"]')!.textContent).toContain('1–2 de 30');
      click(button('Siguiente'));
      expect(store.setPage).toHaveBeenCalledWith(2);
      expect(button('Anterior')!.disabled).toBeTrue();
    });

    it('sends category and status filters to the server', () => {
      const status = host().querySelector('#inv-status') as HTMLSelectElement;
      status.value = 'low';
      status.dispatchEvent(new Event('change'));
      expect(store.setFilters).toHaveBeenCalledWith({ status: 'low' });
    });

    it('says the metrics are unavailable instead of showing zeros', () => {
      render(state({ overview: null }));
      expect(host().textContent).toContain('Las métricas no están disponibles');
      expect(host().querySelector('[aria-label="Alertas de reposición"]')).toBeNull();
    });

    it('shows value, consumption with n and the few-data note, and the monthly chart', () => {
      const pulse = host().querySelector('[aria-label="Pulso del inventario"]')!.textContent!;
      expect(pulse).toContain('1,500.00');
      expect(pulse).toContain('n = 3 movimientos');
      expect(pulse).toContain('pocos datos');
      expect(pulse).toContain('Cable viejo');
      expect(host().querySelector('svg[aria-label="Unidades consumidas por mes"]')).not.toBeNull();
    });

    it('plays the hero video muted and decorative', () => {
    const video = host().querySelector('header video') as HTMLVideoElement;
    expect(video.getAttribute('src')).toBe('assets/videos/inventory.mp4');
    expect(video.getAttribute('poster')).toBe('assets/videos/inventario-poster.jpg');
    expect(video.muted).toBeTrue();
    expect(video.closest('[aria-hidden="true"]')).not.toBeNull();
      expect(host().querySelector('[data-placeholder="inventario-hero.svg"]')).toBeNull();
    });
  });

  describe('states', () => {
    beforeEach(() => create());

    it('shows skeletons while loading, then an empty state with the illustration', () => {
      render(state({ items: [], loading: true }));
      expect(host().querySelector('[aria-label="Cargando inventario"]')).not.toBeNull();
      render(state({ items: [], total: 0 }));
      expect(host().textContent).toContain('Aún no hay ítems en el inventario');
      expect(host().querySelector('img[src$="inventario-vacio.webp"]')).not.toBeNull();
    });

    it('offers to clear filters when they leave nothing', () => {
      render(state({ items: [], total: 0, filters: { ...EMPTY_FILTERS, status: 'low' } }));
      expect(host().textContent).toContain('Ningún ítem coincide con los filtros');
      click(Array.from(host().querySelectorAll('button')).filter((b) => b.textContent?.includes('Limpiar')).pop()!);
      expect(store.clearFilters).toHaveBeenCalled();
    });

    it('shows an error with a retry', () => {
      render(state({ items: [], error: 'No se pudo cargar el inventario.' }));
      expect(host().querySelector('[role="alert"]')!.textContent).toContain('No se pudo cargar el inventario.');
      click(button('Reintentar'));
      expect(store.load).toHaveBeenCalled();
    });
  });

  describe('permissions', () => {
    it('shows every action to a manager', async () => {
      await create(['inventory.manage', 'inventory.consume']);
      expect(button('Nuevo ítem')).not.toBeNull();
      expect(button('Importar')).not.toBeNull();
      expect(host().querySelector('button[aria-label="Nuevo ítem"]')).not.toBeNull();
    });

    it('lets a technician consume but not create, import or enter stock', async () => {
      await create(['inventory.consume']);
      expect(button('Nuevo ítem')).toBeNull();
      expect(button('Importar')).toBeNull();
      expect(button('Entrada')).toBeNull();
      expect(button('Consumir')).not.toBeNull();
      render(state({ selectedId: 1, item: item() }));
      expect(button('Editar')).toBeNull();
      expect(button('Eliminar…')).toBeNull();
      expect(button('Desactivar…')).toBeNull();
    });

    it('offers nothing but reading to a read-only user', async () => {
      await create([]);
      expect(button('Consumir')).toBeNull();
      expect(button('Entrada')).toBeNull();
    });
  });

  describe('item form', () => {
    beforeEach(async () => {
      await create();
      click(button('Nuevo ítem'));
    });

    const submit = () => host().querySelector('form[role="dialog"] button[type="submit"]') as HTMLButtonElement;
    const fill = (overrides: Record<string, string> = {}) => {
      const values: Record<string, string> = { '#if-sku': 'ssd-512', '#if-name': 'SSD 512 GB', '#if-unit': 'unidad', '#if-min': '5', ...overrides };
      for (const [selector, value] of Object.entries(values)) {
        type(selector, value);
      }
    };

    it('starts disabled with no errors shown', () => {
      expect(submit().disabled).toBeTrue();
      expect(message('if-sku-err')).toBe('');
    });

    it('creates the item trimmed, with the SKU in upper case and numbers as numbers', () => {
      fill({ '#if-name': '  SSD 512 GB  ', '#if-cost': '64,90', '#if-initial': '12', '#if-max': '40' });
      expect(submit().disabled).toBeFalse();
      click(submit());
      expect(store.create.calls.mostRecent().args[0]).toEqual(jasmine.objectContaining({
        sku: 'SSD-512', name: 'SSD 512 GB', unit_cost: 64.9, initial_stock: 12, min_stock: 5, max_stock: 40, description: null, category: 'spare_part',
      }));
    });

    it('explains each invalid value in Spanish and keeps submit disabled', () => {
      fill({ '#if-sku': 'a b' });
      expect(message('if-sku-err')).toBe('Usa 3 a 40 caracteres: letras, números, punto, guion o guion bajo.');
      fill({ '#if-sku': 'OK-1', '#if-name': '   ' });
      expect(message('if-name-err')).toBe('Este campo es obligatorio.');
      fill({ '#if-name': 'Algo', '#if-cost': '-3' });
      expect(message('if-cost-err')).toBe('No puede ser negativo.');
      fill({ '#if-cost': '1.234' });
      expect(message('if-cost-err')).toBe('Usa como máximo 2 decimales.');
      fill({ '#if-cost': '', '#if-min': '-1' });
      expect(message('if-min-err')).toBe('Debe ser al menos 0.');
      fill({ '#if-min': '2.5' });
      expect(message('if-min-err')).toBe('Debe ser un número entero.');
      fill({ '#if-min': '5', '#if-initial': '-4' });
      expect(message('if-initial-err')).toBe('Debe ser al menos 0.');
      fill({ '#if-initial': '0', '#if-unit': 'u@' });
      expect(message('if-unit-err')).toBe('Contiene caracteres no permitidos.');
      expect(submit().disabled).toBeTrue();
      click(submit());
      expect(store.create).not.toHaveBeenCalled();
    });

    it('rejects a maximum below the minimum', () => {
      fill({ '#if-min': '10', '#if-max': '4' });
      expect(message('if-max-err')).toBe('El máximo no puede ser menor que el mínimo.');
      expect(submit().disabled).toBeTrue();
      fill({ '#if-max': '10' });
      expect(submit().disabled).toBeFalse();
    });

    it('shows the server message under the field, e.g. a duplicate SKU', () => {
      store.create.and.returnValue(of({ ok: false, fieldErrors: { sku: 'El valor no es válido.' } }));
      fill();
      click(submit());
      expect(message('if-sku-err')).toBe('El valor no es válido.');
    });

    it('blocks a second submit while saving and closes with Escape', () => {
      fill();
      render(state({ busy: true }));
      expect(submit().disabled).toBeTrue();
      expect(submit().textContent).toContain('Guardando');
      document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
      fixture.detectChanges();
      expect(host().querySelector('form[role="dialog"]')).toBeNull();
    });
  });

  describe('movement form', () => {
    beforeEach(async () => {
      await create();
      click(Array.from(host().querySelectorAll('button')).find((b) => b.textContent?.trim() === 'Consumir')!);
    });

    const submit = () => host().querySelector('form[role="dialog"] button[type="submit"]') as HTMLButtonElement;
    const pick = (label: string) => click(Array.from(host().querySelectorAll('form[role="dialog"] [role="group"] button')).find((b) => b.textContent?.trim() === label)!);

    it('starts as a consumption of the item at hand', () => {
      expect(host().querySelector('#mm-title')!.textContent).toContain('Registrar movimiento');
      expect(host().querySelector('form[role="dialog"]')!.textContent).toContain('SSD-512');
      expect(submit().disabled).toBeTrue();
    });

    it('never lets a consumption exceed the stock, and shows the resulting stock', () => {
      type('#mm-quantity', '13');
      expect(message('mm-quantity-err')).toBe('Solo hay 12 disponibles.');
      expect(submit().disabled).toBeTrue();
      type('#mm-quantity', '12');
      expect(submit().disabled).toBeFalse();
      expect(host().querySelector('form[role="dialog"]')!.textContent).toContain('Stock resultante: 0');
    });

    it('rejects zero, negative and decimal quantities', () => {
      for (const [value, text] of [['0', 'Debe ser al menos 1.'], ['-2', 'Debe ser al menos 1.'], ['1.5', 'Debe ser un número entero.']]) {
        type('#mm-quantity', value);
        expect(message('mm-quantity-err')).toBe(text);
      }
    });

    it('sends a consumption linked to a record', () => {
      type('#mm-quantity', '2');
      type('#mm-record', '31');
      type('#mm-notes', '  Cambio de SSD  ');
      click(submit());
      expect(store.move).toHaveBeenCalledWith(1, { kind: 'out', quantity: 2, unit_cost: null, notes: 'Cambio de SSD', record_id: 31, request_id: null });
    });

    it('allows an entry with a cost and a signed adjustment, but never an adjustment below zero stock', () => {
      pick('Entrada');
      type('#mm-quantity', '5');
      type('#mm-cost', '70,5');
      expect(host().querySelector('form[role="dialog"]')!.textContent).toContain('Stock resultante: 17');
      click(submit());
      expect(store.move.calls.mostRecent().args[1]).toEqual(jasmine.objectContaining({ kind: 'in', quantity: 5, unit_cost: 70.5 }));
      // El modal se cierra al registrar: se vuelve a abrir para probar el ajuste.
      click(Array.from(host().querySelectorAll('button')).find((b) => b.textContent?.trim() === 'Consumir')!);
      pick('Ajuste');
      type('#mm-quantity', '0');
      expect(message('mm-quantity-err')).toBe('No puede ser 0.');
      type('#mm-quantity', '-13');
      expect(message('mm-quantity-err')).toBe('Solo hay 12 disponibles.');
      type('#mm-quantity', '-3');
      expect(submit().disabled).toBeFalse();
    });

    it('rejects a negative entry cost', () => {
      pick('Entrada');
      type('#mm-quantity', '1');
      type('#mm-cost', '-1');
      expect(message('mm-cost-err')).toBe('No puede ser negativo.');
      expect(submit().disabled).toBeTrue();
    });
  });

  it('only offers consumption to someone who cannot manage the inventory', async () => {
    await create(['inventory.consume']);
    click(Array.from(host().querySelectorAll('button')).find((b) => b.textContent?.trim() === 'Consumir')!);
    const kinds = Array.from(host().querySelectorAll('form[role="dialog"] [role="group"] button')).map((b) => b.textContent?.trim());
    expect(kinds).toEqual(['Consumo']);
  });

  describe('detail panel', () => {
    const movements: Movement[] = [
      { id: 2, item_id: 1, kind: 'out', quantity: -3, stock_after: 9, unit_cost: null, notes: 'Cambio de SSD', record_id: 4, request_id: null, created_by: 'Luis', created_at: '2026-10-10T10:00:00Z' },
      { id: 1, item_id: 1, kind: 'in', quantity: 12, stock_after: 12, unit_cost: '64.90', notes: 'Carga inicial', record_id: null, request_id: null, created_by: null, created_at: '2026-10-01T10:00:00Z' },
    ];

    beforeEach(async () => {
      await create();
      render(state({ selectedId: 1, item: item(), movements, movementsTotal: 2 }));
    });

    it('shows the level, the history with signed quantities and no delete once it has moved', () => {
      const panel = host().querySelector('[aria-label="Detalle del ítem"]')!.textContent!;
      expect(panel).toContain('Cambio de SSD');
      expect(panel).toContain('-3 → 9');
      expect(panel).toContain('+12 → 12');
      expect(button('Eliminar…')).toBeNull();
    });

    it('asks for confirmation before deactivating', () => {
      click(button('Desactivar…'));
      expect(store.update).not.toHaveBeenCalled();
      expect(host().textContent).toContain('¿Desactivar este ítem?');
      click(button('Confirmar'));
      expect(store.update).toHaveBeenCalledWith(1, { is_active: false }, 'Ítem desactivado.');
    });

    it('asks for confirmation before deleting an item that never moved', () => {
      render(state({ selectedId: 1, item: item(), movements: [], movementsTotal: 0 }));
      click(button('Eliminar…'));
      expect(store.remove).not.toHaveBeenCalled();
      expect(host().textContent).toContain('no se puede deshacer');
      click(button('Confirmar eliminación'));
      expect(store.remove).toHaveBeenCalledWith(1);
    });

    it('offers no stock actions on an inactive item, only reactivation', () => {
      render(state({ selectedId: 1, item: item({ is_active: false }), movements, movementsTotal: 2 }));
      const panel = host().querySelector('[aria-label="Detalle del ítem"]')!;
      expect(Array.from(panel.querySelectorAll('button')).some((b) => b.textContent?.trim() === 'Consumir')).toBeFalse();
      expect(button('Reactivar…')).not.toBeNull();
    });

    it('blocks actions while busy', () => {
      render(state({ selectedId: 1, item: item(), movements, movementsTotal: 2, busy: true }));
      expect((button('Editar') as HTMLButtonElement).disabled).toBeTrue();
    });
  });

  describe('import', () => {
    beforeEach(async () => {
      await create();
      click(button('Importar'));
    });

    const choose = (file: File) => {
      const input = host().querySelector('#im-file') as HTMLInputElement;
      Object.defineProperty(input, 'files', { value: [file], configurable: true });
      input.dispatchEvent(new Event('change'));
      fixture.detectChanges();
    };
    const validate = () => button('Validar') as HTMLButtonElement;
    const importBtn = () => Array.from(host().querySelectorAll('form[role="dialog"] button, section[role="dialog"] button')).find((b) => b.textContent?.trim() === 'Importar') as HTMLButtonElement;

    it('rejects a wrong type, an empty file and an oversized one before sending anything', () => {
      choose(new File(['x'], 'virus.exe'));
      expect(message('im-file-err')).toBe('Solo se admiten archivos .csv o .xlsx.');
      expect(validate().disabled).toBeTrue();
      choose(new File([], 'vacio.csv'));
      expect(message('im-file-err')).toBe('El archivo está vacío.');
      const big = new File(['x'], 'big.csv');
      Object.defineProperty(big, 'size', { value: 6 * 1024 * 1024 });
      choose(big);
      expect(message('im-file-err')).toBe('El archivo supera los 5 MB permitidos.');
      expect(store.importFile).not.toHaveBeenCalled();
    });

    it('validates first, then only allows the real import after a clean dry run', () => {
      const file = new File(['sku,name\nA-1,Algo'], 'items.csv');
      store.importFile.and.returnValue(of({ dry_run: true, success: true, total_rows: 1, created: 0, errors: [] }));
      choose(file);
      expect(importBtn().disabled).toBeTrue();
      click(validate());
      expect(store.importFile).toHaveBeenCalledWith(file, true);
      expect(host().textContent).toContain('1 filas válidas');
      expect(importBtn().disabled).toBeFalse();
      store.importFile.and.returnValue(of({ dry_run: false, success: true, total_rows: 1, created: 1, errors: [] }));
      click(importBtn());
      expect(store.importFile).toHaveBeenCalledWith(file, false);
    });

    it('lists the row errors and keeps the import disabled', () => {
      store.importFile.and.returnValue(of({
        dry_run: true, success: false, total_rows: 3, created: 0,
        errors: [{ row: 2, field: 'unit_cost', message: 'Input should be greater than or equal to 0' }, { row: 4, field: null, message: 'duplicate' }],
      }));
      choose(new File(['x'], 'items.csv'));
      click(validate());
      const alert = host().querySelector('[role="alert"].bg-error-container')!;
      expect(alert.textContent).toContain('2 problema(s) en 3 filas');
      expect(alert.textContent).toContain('Fila 2');
      expect(importBtn().disabled).toBeTrue();
    });

    it('discards the previous validation when another file is chosen', () => {
      store.importFile.and.returnValue(of({ dry_run: true, success: true, total_rows: 1, created: 0, errors: [] }));
      choose(new File(['x'], 'a.csv'));
      click(validate());
      expect(importBtn().disabled).toBeFalse();
      choose(new File(['y'], 'b.csv'));
      expect(importBtn().disabled).toBeTrue();
    });
  });

  describe('contrast inside the .tw-reset shell (AA, 4.5:1)', () => {
    beforeEach(() => create());
    const ratio = (el: Element) => {
      const style = getComputedStyle(el);
      return contrastRatio(flatten(style.color), flatten(style.backgroundColor, '#ffffff'));
    };

    it('keeps the call to action, the toggles and the status chips legible', () => {
      expect(ratio(button('Nuevo ítem')!)).toBeGreaterThanOrEqual(WCAG_AA);
      for (const el of Array.from(host().querySelectorAll('[role="group"] button'))) {
        const style = getComputedStyle(el);
        const background = style.backgroundColor === 'rgba(0, 0, 0, 0)' ? '#ffffff' : flatten(style.backgroundColor);
        expect(contrastRatio(style.color, background)).withContext(el.textContent ?? '').toBeGreaterThanOrEqual(WCAG_AA);
      }
      for (const chip of Array.from(host().querySelectorAll('section[aria-label="Ítems"] li span.rounded-full.px-2'))) {
        expect(ratio(chip)).withContext(chip.textContent ?? '').toBeGreaterThanOrEqual(WCAG_AA);
      }
    });
  });
});
