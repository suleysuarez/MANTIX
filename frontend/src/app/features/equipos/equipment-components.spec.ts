import { ComponentFixture, TestBed, fakeAsync, tick } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';

import { DetailState } from '../../core/equipment-detail.store';
import { Equipment, EquipmentSummary } from '../../core/equipment.service';
import { EMPTY_FILTERS, SaveRequest } from '../../core/equipment.store';
import { EquipmentDetailDrawerComponent, warrantyLabel } from './equipment-detail-drawer.component';
import {
  EquipmentFormModalComponent,
  MAX_FILE_BYTES,
  fileProblem,
  warrantyOrder,
} from './equipment-form-modal.component';
import { EquipmentGridComponent } from './equipment-grid.component';
import { EquipmentPaginationComponent } from './equipment-pagination.component';
import { EquipmentSummaryCardsComponent } from './equipment-summary-cards.component';
import { EquipmentTableComponent } from './equipment-table.component';
import { EquipmentToolbarComponent } from './equipment-toolbar.component';
import { FormControl, FormGroup } from '@angular/forms';

const laptop = (overrides: Partial<Equipment> = {}): Equipment => ({
  id: 1,
  asset_tag: 'EQ-001',
  serial_number: 'SN-1',
  equipment_type_id: 1,
  equipment_type: { id: 1, code: 'LAPTOP', name: 'Portátil' },
  brand: 'Dell',
  model: 'Latitude 5440',
  description: 'Intel Core i7 · 16GB',
  status: 'assigned',
  purchase_date: '2025-01-15',
  purchase_cost: '1250.00',
  warranty_start_date: null,
  warranty_end_date: '2099-01-01',
  created_at: '2025-01-10T08:00:00Z',
  current_location: { id: 3, code: 'P3', name: 'Piso 3 - Desarrollo' },
  current_custodian: { id: 8, full_name: 'Carlos Rivera', email: 'carlos@example.com' },
  last_maintenance: { performed_at: '2025-02-10T09:00:00Z', work_type: 'preventive', result: 'ok', technician_name: 'Laura Peña' },
  ...overrides,
});

function text(fixture: ComponentFixture<unknown>): string {
  return (fixture.nativeElement as HTMLElement).textContent?.replace(/\s+/g, ' ').trim() ?? '';
}

function click(fixture: ComponentFixture<unknown>, selector: string, index = 0): void {
  const elements = (fixture.nativeElement as HTMLElement).querySelectorAll<HTMLElement>(selector);
  elements[index].click();
  fixture.detectChanges();
}

describe('EquipmentSummaryCardsComponent', () => {
  let fixture: ComponentFixture<EquipmentSummaryCardsComponent>;
  const summary: EquipmentSummary = {
    total: 28,
    by_status: { assigned: 18, in_storage: 4, in_repair: 4, retired: 2 },
  };

  beforeEach(() => {
    fixture = TestBed.createComponent(EquipmentSummaryCardsComponent);
    fixture.componentInstance.summary = summary;
    fixture.detectChanges();
  });

  it('shows the totals, grouped counts and the operational rate', () => {
    const content = text(fixture);
    expect(content).toContain('28');
    expect(content).toContain('22'); // assigned + in_storage
    expect(content).toContain('78.6% tasa');
    expect(fixture.componentInstance.maintenance).toBe(4);
    expect(fixture.componentInstance.offline).toBe(2);
  });

  it('emits the status filter of the clicked card', () => {
    const emitted: string[] = [];
    fixture.componentInstance.filterChange.subscribe((value) => emitted.push(value));

    click(fixture, 'button', 0);
    click(fixture, 'button', 1);
    click(fixture, 'button', 2);
    click(fixture, 'button', 3);

    expect(emitted).toEqual(['', 'assigned,in_storage', 'in_repair', 'lost,retired,disposed']);
  });

  it('highlights the card that matches the active filter', () => {
    fixture.componentRef.setInput('statusFilter', 'in_repair');
    fixture.detectChanges();
    const buttons = (fixture.nativeElement as HTMLElement).querySelectorAll('button');
    expect(Array.from(buttons).map((b) => b.getAttribute('aria-pressed'))).toEqual(['false', 'false', 'true', 'false']);
  });

  it('copes with a missing summary and an empty catalog', () => {
    fixture.componentInstance.summary = null;
    expect(fixture.componentInstance.rate).toBe('0%');
    fixture.componentInstance.summary = { total: 0, by_status: {} };
    expect(fixture.componentInstance.rate).toBe('0%');
  });
});

describe('EquipmentPaginationComponent', () => {
  let fixture: ComponentFixture<EquipmentPaginationComponent>;

  function render(page: number, total: number, size = 10): void {
    fixture = TestBed.createComponent(EquipmentPaginationComponent);
    Object.assign(fixture.componentInstance, { page, total, pageSize: size });
    fixture.detectChanges();
  }

  it('describes the visible range', () => {
    render(2, 28);
    expect(text(fixture)).toContain('Equipos 11–20 de 28');
    render(3, 28);
    expect(text(fixture)).toContain('Equipos 21–28 de 28');
  });

  it('gives a single page a meaningful summary instead of a degenerate range', () => {
    render(1, 1);
    expect(text(fixture)).toContain('1 equipo en el inventario');
    render(1, 3);
    expect(text(fixture)).toContain('3 equipos en el inventario');
  });

  it('says when the total comes from active filters', () => {
    fixture = TestBed.createComponent(EquipmentPaginationComponent);
    Object.assign(fixture.componentInstance, { page: 1, total: 2, pageSize: 10, filtered: true });
    fixture.detectChanges();
    expect(text(fixture)).toContain('2 equipos con los filtros aplicados');
  });

  it('says so when there is nothing to show and hides the page buttons', () => {
    render(1, 0);
    expect(text(fixture)).toContain('Sin resultados');
    expect((fixture.nativeElement as HTMLElement).querySelectorAll('button').length).toBe(0);
  });

  it('emits previous, numbered and next pages and disables the edges', () => {
    render(1, 28);
    const pages: number[] = [];
    fixture.componentInstance.pageChange.subscribe((value) => pages.push(value));
    const buttons = (fixture.nativeElement as HTMLElement).querySelectorAll<HTMLButtonElement>('button');

    expect(buttons[0].getAttribute('aria-label')).not.toBe('Página anterior'); // no previous button on page 1
    expect(buttons[0].getAttribute('aria-current')).toBe('page');
    buttons[1].click(); // page 2
    buttons[buttons.length - 1].click(); // next

    expect(pages).toEqual([2, 2]);
  });
});

describe('EquipmentTableComponent / EquipmentGridComponent', () => {
  it('renders rows with location, status and last maintenance', () => {
    const fixture = TestBed.createComponent(EquipmentTableComponent);
    fixture.componentInstance.equipment = [laptop(), laptop({ id: 2, asset_tag: 'EQ-002', current_location: null, last_maintenance: null, status: 'in_repair' })];
    fixture.detectChanges();

    const content = text(fixture);
    expect(content).toContain('Dell Latitude 5440');
    expect(content).toContain('EQ-001');
    expect(content).toContain('Piso 3 - Desarrollo');
    expect(content).toContain('Asignado');
    expect(content).toContain('10 feb 2025');
    expect(content).toContain('Por Laura Peña');
    expect(content).toContain('Sin ubicación');
    expect(content).toContain('En mantenimiento');
    expect(content).toContain('Sin registros');
  });

  it('shows different empty states for an empty catalog and for no matches', () => {
    const fixture = TestBed.createComponent(EquipmentTableComponent);
    fixture.detectChanges();
    expect(text(fixture)).toContain('Aún no hay equipos registrados');

    fixture.componentRef.setInput('filtered', true);
    fixture.detectChanges();
    expect(text(fixture)).toContain('Ningún equipo coincide');
  });

  it('shows placeholders instead of rows while loading', () => {
    const fixture = TestBed.createComponent(EquipmentTableComponent);
    fixture.componentInstance.loading = true;
    fixture.detectChanges();
    expect((fixture.nativeElement as HTMLElement).querySelectorAll('.animate-pulse').length).toBe(5);
  });

  it('emits view and edit, and hides edit without permission', () => {
    const fixture = TestBed.createComponent(EquipmentTableComponent);
    const item = laptop();
    fixture.componentInstance.equipment = [item];
    const viewed: Equipment[] = [];
    const edited: Equipment[] = [];
    fixture.componentInstance.view.subscribe((value) => viewed.push(value));
    fixture.componentInstance.edit.subscribe((value) => edited.push(value));
    fixture.detectChanges();

    expect((fixture.nativeElement as HTMLElement).querySelector('[title="Editar"]')).toBeNull();
    click(fixture, '[title="Ver detalle"]');
    fixture.componentRef.setInput('canManage', true);
    fixture.detectChanges();
    click(fixture, '[title="Editar"]');

    expect(viewed).toEqual([item]);
    expect(edited).toEqual([item]);
  });

  it('the grid shows the same facts plus the custodian', () => {
    const fixture = TestBed.createComponent(EquipmentGridComponent);
    fixture.componentInstance.equipment = [laptop()];
    fixture.detectChanges();

    const content = text(fixture);
    expect(content).toContain('Carlos Rivera');
    expect(content).toContain('Piso 3 - Desarrollo');
    expect(content).toContain('EQ-001');
  });
});

describe('EquipmentToolbarComponent', () => {
  let fixture: ComponentFixture<EquipmentToolbarComponent>;

  beforeEach(() => {
    fixture = TestBed.createComponent(EquipmentToolbarComponent);
    Object.assign(fixture.componentInstance, {
      filters: EMPTY_FILTERS,
      types: [{ id: 1, code: 'LAPTOP', name: 'Portátil' }],
    });
    fixture.detectChanges();
  });

  it('debounces typing into a single search change', fakeAsync(() => {
    const searches: unknown[] = [];
    fixture.componentInstance.filtersChange.subscribe((value) => searches.push(value));
    const input = (fixture.nativeElement as HTMLElement).querySelector<HTMLInputElement>('input[type=search]')!;

    for (const value of ['l', 'la', 'lap']) {
      input.value = value;
      input.dispatchEvent(new Event('input'));
      tick(100);
    }
    expect(searches).toEqual([]);
    tick(300);

    expect(searches).toEqual([{ search: 'lap' }]);
  }));

  it('turns select values into typed filters', () => {
    const changes: unknown[] = [];
    fixture.componentInstance.filtersChange.subscribe((value) => changes.push(value));
    const selects = (fixture.nativeElement as HTMLElement).querySelectorAll<HTMLSelectElement>('select');

    selects[0].value = '1';
    selects[0].dispatchEvent(new Event('change'));
    selects[1].value = 'in_repair';
    selects[1].dispatchEvent(new Event('change'));

    expect(changes).toEqual([{ typeId: 1 }, { status: 'in_repair' }]);
  });

  it('only offers the export menu with permission and emits the chosen format', () => {
    expect(text(fixture)).not.toContain('Exportar');
    fixture.componentRef.setInput('canExport', true);
    fixture.detectChanges();
    const formats: string[] = [];
    fixture.componentInstance.exportRequested.subscribe((value) => formats.push(value));

    click(fixture, '[aria-haspopup=menu]');
    click(fixture, '[role=menuitem]', 1);

    expect(formats).toEqual(['csv']);
  });

  it('switches the view and resets the filters', () => {
    const views: string[] = [];
    let resets = 0;
    fixture.componentInstance.viewChange.subscribe((value) => views.push(value));
    fixture.componentInstance.filtersReset.subscribe(() => resets++);

    click(fixture, '[role=group] button', 1);
    click(fixture, '[aria-label="Restablecer filtros"]');

    expect(views).toEqual(['grid']);
    expect(resets).toBe(1);
  });
});

describe('EquipmentFormModalComponent', () => {
  let fixture: ComponentFixture<EquipmentFormModalComponent>;
  let submitted: SaveRequest[];

  function open(equipment: Equipment | null = null): void {
    TestBed.configureTestingModule({ providers: [provideHttpClient(), provideHttpClientTesting()] });
    fixture = TestBed.createComponent(EquipmentFormModalComponent);
    fixture.componentInstance.equipment = equipment;
    fixture.componentInstance.types = [{ id: 1, code: 'LAPTOP', name: 'Portátil' }];
    fixture.componentInstance.locations = [{ id: 3, code: 'P3', name: 'Piso 3', kind: 'floor', parent_id: null }];
    submitted = [];
    fixture.componentInstance.submitted.subscribe((value) => submitted.push(value));
    fixture.detectChanges();
  }

  it('does not submit an incomplete form and shows what is missing', () => {
    open();

    fixture.componentInstance.submit();
    fixture.detectChanges();

    expect(submitted).toEqual([]);
    const content = text(fixture);
    expect(content).toContain('Indica el código de activo');
    expect(content).toContain('Elige una categoría');
    expect(content).toContain('Indica la marca');
  });

  it('submits a trimmed payload with the extras for a new item', () => {
    open();
    fixture.componentInstance.form.patchValue({
      asset_tag: ' EQ-029 ', equipment_type_id: 1, brand: ' Dell ', model: 'Latitude',
      serial_number: '', description: '  ', location_id: 3, purchase_cost: 99.5,
    });
    fixture.componentInstance.custodian.set({ id: 8, full_name: 'Carlos', email: 'c@x.co' });
    const file = new File(['%PDF-'], 'ficha.pdf');
    fixture.componentInstance.addFiles({ 0: file, length: 1, item: () => file } as unknown as FileList);

    fixture.componentInstance.submit();

    expect(submitted.length).toBe(1);
    expect(submitted[0]).toEqual(jasmine.objectContaining({ id: null, locationId: 3, custodianId: 8, files: [file] }));
    expect(submitted[0].payload).toEqual(jasmine.objectContaining({
      asset_tag: 'EQ-029', brand: 'Dell', serial_number: null, description: null, purchase_cost: 99.5,
      status: 'in_storage',
    }));
  });

  it('edits an existing item: the code is locked and location/attachments are not offered', () => {
    open(laptop());

    expect(fixture.componentInstance.form.controls.asset_tag.disabled).toBeTrue();
    expect(text(fixture)).toContain('Editar equipo');
    expect(text(fixture)).not.toContain('Adjuntos');

    fixture.componentInstance.form.patchValue({ brand: 'HP' });
    fixture.componentInstance.submit();

    expect(submitted[0].id).toBe(1);
    expect(submitted[0].payload.asset_tag).toBe('EQ-001');
    expect(submitted[0].payload.brand).toBe('HP');
    expect(submitted[0].payload.purchase_cost).toBe(1250);
  });

  it('rejects a warranty that ends before it starts', () => {
    open();
    const form = fixture.componentInstance.form;
    form.patchValue({
      asset_tag: 'A', equipment_type_id: 1, brand: 'b', model: 'm',
      warranty_start_date: '2025-06-01', warranty_end_date: '2025-01-01',
    });
    form.controls.warranty_end_date.markAsTouched();
    fixture.componentInstance.submit();
    fixture.detectChanges();

    expect(submitted).toEqual([]);
    expect(text(fixture)).toContain('no puede terminar antes de empezar');
  });

  it('closes on Escape unless it is saving', () => {
    open();
    let closed = 0;
    fixture.componentInstance.closed.subscribe(() => closed++);

    fixture.componentInstance.onEscape();
    fixture.componentInstance.saving = true;
    fixture.componentInstance.onEscape();

    expect(closed).toBe(1);
  });

  it('keeps only valid attachments, no duplicates and at most five', () => {
    open();
    const ok = (name: string, size = 10) => new File([new Uint8Array(size)], name);
    const list = (...files: File[]) => ({ length: files.length, item: (i: number) => files[i], ...Object.fromEntries(files.map((f, i) => [i, f])) }) as unknown as FileList;
    // Array.from(list) needs an iterable or array-like with length
    fixture.componentInstance.addFiles(list(ok('a.pdf'), ok('b.png'), ok('virus.exe'), ok('a.pdf')));

    expect(fixture.componentInstance.files().map((f) => f.name)).toEqual(['a.pdf', 'b.png']);
    expect(fixture.componentInstance.fileProblems()[0]).toContain('virus.exe');

    fixture.componentInstance.addFiles(list(ok('c.pdf'), ok('d.pdf'), ok('e.pdf'), ok('f.pdf')));
    expect(fixture.componentInstance.files().length).toBe(5);
    expect(fixture.componentInstance.fileProblems()[0]).toContain('máximo 5');

    fixture.componentInstance.removeFile(0);
    expect(fixture.componentInstance.files().length).toBe(4);
  });
});

describe('form helpers', () => {
  it('validates attachment type, emptiness and size', () => {
    expect(fileProblem(new File(['x'], 'foto.JPG'))).toBeNull();
    expect(fileProblem(new File(['x'], 'run.exe'))).toContain('tipo no permitido');
    expect(fileProblem(new File([], 'vacio.pdf'))).toContain('vacío');
    const big = new File([new Uint8Array(MAX_FILE_BYTES + 1)], 'grande.pdf');
    expect(fileProblem(big)).toContain('10 MB');
  });

  it('warrantyOrder flags only inverted ranges', () => {
    const group = (start: string, end: string) =>
      new FormGroup({ warranty_start_date: new FormControl(start), warranty_end_date: new FormControl(end) });
    expect(warrantyOrder(group('2025-01-01', '2024-01-01'))).toEqual({ warrantyOrder: true });
    expect(warrantyOrder(group('2025-01-01', '2025-01-01'))).toBeNull();
    expect(warrantyOrder(group('', '2024-01-01'))).toBeNull();
  });

  it('describes the warranty relative to today', () => {
    const today = new Date(2026, 5, 15);
    expect(warrantyLabel('2027-01-01', today)).toEqual({ text: 'Vigente hasta 01 ene 2027', expired: false });
    expect(warrantyLabel('2026-06-15', today)?.expired).toBeFalse();
    expect(warrantyLabel('2026-01-01', today)).toEqual({ text: 'Vencida el 01 ene 2026', expired: true });
    expect(warrantyLabel(null, today)).toBeNull();
  });
});

describe('EquipmentDetailDrawerComponent', () => {
  let fixture: ComponentFixture<EquipmentDetailDrawerComponent>;

  const state = (overrides: Partial<DetailState> = {}): DetailState => ({
    equipment: laptop(),
    tickets: [{ id: 84, ticket_number: 'TCK-2025-000084', equipment_id: 1, title: 'Falla de batería', priority: 'high', status: 'resolved', created_at: '2025-02-01T10:00:00Z' }],
    schedules: [],
    attachments: [{ id: 3, file_name: 'ficha.pdf', mime_type: 'application/pdf', file_size: 2048, uploaded_by_user_id: 1, created_at: '' }],
    loading: false, busy: false, error: '', notice: '',
    ...overrides,
  });

  function render(overrides: Partial<DetailState> = {}, abilities: Partial<EquipmentDetailDrawerComponent> = {}): void {
    TestBed.configureTestingModule({
      providers: [provideRouter([]), provideHttpClient(), provideHttpClientTesting()],
    });
    fixture = TestBed.createComponent(EquipmentDetailDrawerComponent);
    fixture.componentInstance.state = state(overrides);
    Object.assign(fixture.componentInstance, abilities);
    fixture.detectChanges();
  }

  it('shows the technical sheet, custodian, history and attachments', () => {
    render({}, { canReadMaintenance: true });

    const content = text(fixture);
    expect(content).toContain('EQ-001');
    expect(content).toContain('Dell Latitude 5440');
    expect(content).toContain('SN-1');
    expect(content).toContain('Piso 3 - Desarrollo');
    expect(content).toContain('Carlos Rivera');
    expect(content).toContain('Vigente hasta 01 ene 2099');
    expect(content).toContain('Falla de batería');
    expect(content).toContain('TCK-2025-000084');
    expect(content).toContain('ficha.pdf');
    expect(content).toContain('Último trabajo: Preventivo');
  });

  it('offers management actions only with the matching permissions', () => {
    render();
    let content = text(fixture);
    expect(content).not.toContain('Reasignar');
    expect(content).not.toContain('Adjuntar');
    expect(content).not.toContain('Crear ticket');
    expect(content).not.toContain('Programar mantenimiento');

    fixture.componentRef.setInput('canManage', true);
    fixture.componentRef.setInput('canAttach', true);
    fixture.componentRef.setInput('canCreateTicket', true);
    fixture.componentRef.setInput('canSchedule', true);
    fixture.detectChanges();
    content = text(fixture);
    expect(content).toContain('Reasignar');
    expect(content).toContain('Adjuntar');
    expect(content).toContain('Crear ticket');
    expect(content).toContain('Programar mantenimiento');
  });

  it('links «Crear ticket» to the maintenance screen with the equipment preselected', () => {
    render({}, { canCreateTicket: true });
    const link = (fixture.nativeElement as HTMLElement).querySelector<HTMLAnchorElement>('footer a')!;
    expect(link.getAttribute('href')).toContain('/maintenance');
    expect(link.getAttribute('href')).toContain('equipmentId=1');
  });

  it('handles an equipment with no custodian, location or history', () => {
    render(
      { equipment: laptop({ current_custodian: null, current_location: null, last_maintenance: null, warranty_end_date: null }), tickets: [], attachments: [] },
      { canReadMaintenance: true, canManage: true },
    );

    const content = text(fixture);
    expect(content).toContain('Sin custodio asignado');
    expect(content).toContain('Sin ubicación');
    expect(content).toContain('Este equipo aún no tiene tickets');
    expect(content).toContain('Sin archivos adjuntos');
    expect(content).toContain('Sin garantía registrada');
    expect(content).toContain('Asignar');
  });

  it('always lists the creation as the first event of the history and counts it', () => {
    render(
      { equipment: laptop(), tickets: [], attachments: [] },
      { canReadMaintenance: true },
    );

    const content = text(fixture);
    expect(content).toContain('Historial (1 evento)');
    expect(content).toContain('Equipo registrado en el inventario');
    expect(content).toContain('Creación');
  });

  it('shows errors and notices from the store', () => {
    render({ error: 'No se pudo cambiar la ubicación.', notice: 'Custodio actualizado.' });
    const content = text(fixture);
    expect(content).toContain('No se pudo cambiar la ubicación.');
    expect(content).toContain('Custodio actualizado.');
  });

  it('emits close, download and relocation events', () => {
    render({}, { canManage: true, locations: [{ id: 9, code: 'R9', name: 'Room 9', kind: 'room', parent_id: null }] });
    let closes = 0;
    const downloads: unknown[] = [];
    const moves: number[] = [];
    fixture.componentInstance.closed.subscribe(() => closes++);
    fixture.componentInstance.download.subscribe((value) => downloads.push(value));
    fixture.componentInstance.relocated.subscribe((value) => moves.push(value));

    click(fixture, '[aria-label="Cerrar detalle"]');
    click(fixture, 'li button'); // the attachment row
    fixture.componentInstance.relocating.set(true);
    fixture.detectChanges();
    const select = (fixture.nativeElement as HTMLElement).querySelector<HTMLSelectElement>('select[aria-label="Nueva ubicación"]')!;
    select.value = '9';
    select.dispatchEvent(new Event('change'));
    fixture.detectChanges();
    const save = Array.from((fixture.nativeElement as HTMLElement).querySelectorAll('button')).find((b) => b.textContent?.trim() === 'Guardar')!;
    save.click();

    expect(closes).toBe(1);
    expect(downloads.length).toBe(1);
    expect(moves).toEqual([9]);
  });

  it('validates and emits a preventive plan', () => {
    render({}, { canSchedule: true });
    const plans: unknown[] = [];
    fixture.componentInstance.scheduled.subscribe((value) => plans.push(value));

    fixture.componentInstance.submitPlan(); // no date yet
    expect(plans).toEqual([]);

    fixture.componentInstance.plan.patchValue({ first_due: '2026-12-01', interval_days: 30, remind_days_before: 40 });
    fixture.componentInstance.submitPlan(); // reminder longer than the interval
    expect(plans).toEqual([]);

    fixture.componentInstance.plan.patchValue({ remind_days_before: 7 });
    fixture.componentInstance.submitPlan();

    expect(plans.length).toBe(1);
    expect(plans[0]).toEqual(jasmine.objectContaining({ equipment_id: 1, interval_days: 30, remind_days_before: 7, title: 'Mantenimiento preventivo' }));
    expect(String((plans[0] as { first_due_at: string }).first_due_at)).toMatch(/^2026-12-01T/);
  });
});
