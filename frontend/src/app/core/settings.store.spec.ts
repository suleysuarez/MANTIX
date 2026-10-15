import { HttpErrorResponse } from '@angular/common/http';
import { TestBed } from '@angular/core/testing';
import { Subject, of, throwError } from 'rxjs';

import { CategoryAdmin, PriorityAdmin, SettingsService, SystemHealth } from './settings.service';
import { SettingsState, SettingsStore } from './settings.store';
import { ToastService } from './toast.service';

const category = (over: Partial<CategoryAdmin> = {}): CategoryAdmin => ({ id: 1, code: 'printers', name: 'Impresoras', is_active: true, usage: 0, created_at: '2026-10-01T00:00:00Z', ...over });
const priority: PriorityAdmin = { id: 2, code: 'high', name: 'Alta', description: null, level: 3, sla_hours: 24, is_active: true };

describe('SettingsStore', () => {
  let api: jasmine.SpyObj<SettingsService>;
  let toasts: ToastService;
  let store: SettingsStore;
  let latest: SettingsState;

  beforeEach(() => {
    api = jasmine.createSpyObj('SettingsService', ['health', 'categories', 'createCategory', 'updateCategory', 'deleteCategory', 'priorities', 'updatePriority']);
    api.health.and.returnValue(of({ overall: 'ok' } as SystemHealth));
    api.categories.and.returnValue(of([category()]));
    api.priorities.and.returnValue(of([priority]));
    TestBed.configureTestingModule({ providers: [SettingsStore, { provide: SettingsService, useValue: api }] });
    toasts = TestBed.inject(ToastService);
    store = TestBed.inject(SettingsStore);
    store.state$.subscribe((state) => (latest = state));
  });

  it('loads health, categories and priorities', () => {
    store.loadAll();
    expect(latest.health?.overall).toBe('ok');
    expect(latest.categories.length).toBe(1);
    expect(latest.priorities[0].sla_hours).toBe(24);
    expect(latest.healthLoading).toBeFalse();
  });

  it('shows a readable error when health cannot be read', () => {
    api.health.and.returnValue(throwError(() => new HttpErrorResponse({ status: 500 })));
    store.loadHealth();
    expect(latest.healthError).toContain('servidor');
    expect(latest.health).toBeNull();
  });

  it('creates a category, toasts and reloads the list', () => {
    api.createCategory.and.returnValue(of(category()));
    const done = jasmine.createSpy('done');
    store.createCategory({ code: 'printers', name: 'Impresoras' }, done);
    expect(toasts.toasts()[0].message).toBe('Categoría creada.');
    expect(api.categories).toHaveBeenCalled();
    expect(done).toHaveBeenCalled();
  });

  it('keeps the form and maps server field errors on a 422', () => {
    const body = { code: 'validation_error', errors: [{ field: 'name', message: 'String should have at least 3 characters', type: 'string_too_short' }] };
    api.createCategory.and.returnValue(throwError(() => new HttpErrorResponse({ status: 422, error: body })));
    const done = jasmine.createSpy('done');
    store.createCategory({ code: 'x_y', name: 'ab' }, done);
    expect(done).not.toHaveBeenCalled();
    expect(latest.fieldErrors['name']).toBe('Debe tener al menos 3 caracteres.');
    expect(toasts.toasts()[0].kind).toBe('error');
    expect(latest.saving).toBeFalse();
  });

  it('explains a duplicate (409) in Spanish without the server text', () => {
    api.createCategory.and.returnValue(throwError(() => new HttpErrorResponse({ status: 409, error: { code: 'conflict', detail: "category 'printers' already exists" } })));
    store.createCategory({ code: 'printers', name: 'Impresoras' }, () => undefined);
    expect(toasts.toasts()[0].message).toBe('Ya existe un registro con ese identificador.');
  });

  it('explains why a used category cannot be deleted', () => {
    api.deleteCategory.and.returnValue(throwError(() => new HttpErrorResponse({ status: 409, error: { code: 'conflict', detail: 'the category is used by 3 request(s) and cannot be deleted' } })));
    store.deleteCategory(category({ usage: 3 }));
    expect(toasts.toasts()[0].message).toContain('desactívala');
  });

  it('ignores a second write while one is in flight', () => {
    const gate = new Subject<CategoryAdmin>();
    api.updateCategory.and.returnValue(gate);
    store.toggleCategory(category());
    store.toggleCategory(category());
    expect(api.updateCategory).toHaveBeenCalledTimes(1);
    expect(latest.saving).toBeTrue();
    gate.next(category({ is_active: false }));
    gate.complete();
    expect(latest.saving).toBeFalse();
    expect(api.updateCategory).toHaveBeenCalledWith(1, { is_active: false });
  });

  it('updates a priority and reloads', () => {
    api.updatePriority.and.returnValue(of(priority));
    const done = jasmine.createSpy('done');
    store.updatePriority(priority, { sla_hours: null }, done);
    expect(api.updatePriority).toHaveBeenCalledWith(2, { sla_hours: null });
    expect(done).toHaveBeenCalled();
    expect(toasts.toasts()[0].message).toBe('Prioridad actualizada.');
  });
});
