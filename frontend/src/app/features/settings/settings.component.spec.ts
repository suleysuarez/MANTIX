import { Component } from '@angular/core';
import { ComponentFixture, TestBed, fakeAsync, flush } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { BehaviorSubject } from 'rxjs';

import { LocalProfileService } from '../../core/local-profile.service';
import { CategoryAdmin, PriorityAdmin, SystemHealth } from '../../core/settings.service';
import { SettingsState, SettingsStore } from '../../core/settings.store';
import { WCAG_AA, contrastRatio, flatten } from '../dashboard/contrast';
import { SettingsComponent } from './settings.component';

const health: SystemHealth = {
  generated_at: '2026-10-14T12:00:00Z',
  overall: 'warning',
  environment: { name: 'production', version: '0.2.0', rate_limit_per_minute: 120, max_upload_mb: 10, reminder_interval_minutes: 60, log_level: 'INFO', scheduler_enabled: true },
  users: { total: 10, active: 8, inactive: 2, without_role: 3 },
  roles: [{ id: 1, code: 'ADMIN', name: 'Administrador', is_active: true, users: 1, permissions: 20 }],
  audit: { last_24h: 4, recent: [{ id: 1, action: 'category.created', entity_type: 'request_category', entity_id: 1, by: 'Ana', at: '2026-10-14T11:00:00Z' }] },
  jobs: [{ id: 'j', name: 'Preventive maintenance reminders', running: true, interval_minutes: 60, next_run_at: '2026-10-14T13:00:00Z', last_run_at: null, last_status: 'never', last_detail: null }],
  integrations: [
    { key: 'database', name: 'Base de datos', status: 'ok', detail: 'Conectada', latency_ms: 12 },
    { key: 'storage', name: 'Almacenamiento de adjuntos', status: 'warning', detail: 'La carpeta aún no existe', latency_ms: null },
  ],
};
const categories: CategoryAdmin[] = [
  { id: 1, code: 'printers', name: 'Impresoras', is_active: true, usage: 0, created_at: '2026-10-01T00:00:00Z' },
  { id: 2, code: 'network', name: 'Redes', is_active: true, usage: 4, created_at: '2026-10-01T00:00:00Z' },
];
const priorities: PriorityAdmin[] = [{ id: 2, code: 'high', name: 'Alta', description: null, level: 3, sla_hours: 24, is_active: true }];

function state(over: Partial<SettingsState> = {}): SettingsState {
  return {
    health, healthLoading: false, healthError: '', categories, categoriesLoading: false, categoriesError: '',
    priorities, prioritiesLoading: false, prioritiesError: '', saving: false, fieldErrors: {},
    organization: { company_name: 'Mantix', configured: false, updated_at: null },
    organizationLoading: false, organizationError: '', ...over,
  };
}

@Component({ standalone: true, imports: [SettingsComponent], template: '<div class="tw-reset"><app-settings /></div>' })
class HostComponent {}

describe('SettingsComponent', () => {
  let subject: BehaviorSubject<SettingsState>;
  let store: jasmine.SpyObj<SettingsStore>;
  let fixture: ComponentFixture<HostComponent>;

  const host = () => fixture.nativeElement as HTMLElement;
  const render = (value: SettingsState) => {
    subject.next(value);
    fixture.detectChanges();
  };
  const click = (el: Element | null | undefined) => {
    (el as HTMLElement).click();
    fixture.detectChanges();
  };
  const button = (text: string) => Array.from(host().querySelectorAll('button')).find((b) => b.textContent?.trim().startsWith(text));
  /** Abre la ventana que contiene lo que se prueba (las secciones ya no son pestañas de la pantalla). */
  const goTo = (label: string) => {
    const bySuffix = (text: string) => Array.from(host().querySelectorAll('button')).find((b) => b.textContent?.includes(text));
    if (label === 'Organización') {
      click(bySuffix('organización'));
    } else if (label === 'Parámetros') {
      click(bySuffix('Ver detalles'));
    } else {
      click(bySuffix('catálogos'));
      click(Array.from(host().querySelectorAll('[role="tab"]')).find((t) => t.textContent?.includes(label)));
    }
  };
  const type = (selector: string, value: string) => {
    const input = host().querySelector(selector) as HTMLInputElement;
    input.value = value;
    input.dispatchEvent(new Event('input'));
    fixture.detectChanges();
  };

  async function create(canManage = true, initial = state()) {
    subject = new BehaviorSubject(initial);
    store = Object.assign(
      jasmine.createSpyObj('SettingsStore', ['loadAll', 'loadHealth', 'saveOrganization', 'createCategory', 'renameCategory', 'toggleCategory', 'deleteCategory', 'updatePriority']),
      { state$: subject },
    );
    TestBed.configureTestingModule({
      providers: [
        provideRouter([]),
        { provide: SettingsStore, useValue: store },
        { provide: LocalProfileService, useValue: { can: () => Promise.resolve(canManage) } },
      ],
    });
    fixture = TestBed.createComponent(HostComponent);
    document.body.appendChild(host());
    fixture.detectChanges();
    await fixture.whenStable();
    fixture.detectChanges();
  }

  afterEach(() => host().remove());

  describe('screen', () => {
    beforeEach(async () => create());

    const flat = (selector: string) => host().querySelector(selector)!.textContent!.replace(/\s+/g, ' ');

    it('is a single screen with the seven blocks of the layout', () => {
      const titles = Array.from(host().querySelectorAll('section h2')).map((h) => h.textContent!.trim());
      expect(titles).toEqual([
        'Configuración general', 'Usuarios y roles', 'Integraciones', 'Mantenimiento',
        'Salud del sistema', 'Tareas programadas', 'Roles y permisos',
      ]);
      expect(host().querySelector('nav[aria-label="Secciones de configuración"]')).toBeNull();
      expect(store.loadAll).toHaveBeenCalled();
    });

    it('shows the general parameters and the real organization name', () => {
      const text = host().textContent!;
      expect(text).toContain('Mantix');
      expect(text).toContain('América/Bogotá (UTC-5)');
      expect(text).toContain('DD/MM/AAAA');
      expect(text).not.toContain('Moneda');
    });

    it('summarises users and roles with a link to manage them', () => {
      const card = flat('[aria-labelledby="cfg-users"]');
      expect(card).toContain('Total de usuarios10');
      expect(card).toContain('Roles definidos1');
      expect(card).toContain('Usuarios activos8');
      expect(card).toContain('Usuarios inactivos2');
      expect(host().querySelector('a[href="/usuarios"]')).not.toBeNull();
    });

    it('shows each integration with its state in words, and its latency in the health card', () => {
      const text = host().textContent!;
      expect(text).toContain('Base de datos');
      expect(text).toContain('Conectada');
      expect(text).toContain('Atención');
      expect(text).toContain('12 ms');
    });

    it('shows the overall state with text, and who is waiting for a role', () => {
      const card = flat('[aria-labelledby="cfg-health"]');
      expect(card).toContain('Atención');
      expect(card).toContain('Esperan autorización');
      expect(host().querySelector('a[href="/admin/pending-users"]')).not.toBeNull();
    });

    it('lists the scheduled tasks in Spanish with their frequency', () => {
      const jobs = flat('[aria-labelledby="cfg-jobs"]');
      expect(jobs).toContain('Cada hora');
      expect(jobs).toContain('Aún no se ejecuta');
      expect(jobs).toContain('1 tarea programada');
    });

    it('lists roles with users and permissions, and the latest audit entries in plain Spanish', () => {
      const roles = flat('[aria-labelledby="cfg-roles"]');
      expect(roles).toContain('Administrador');
      expect(roles).toContain('20 permisos');
      expect(roles).toContain('1 usuario');
      expect(roles).toContain('Ana');
      expect(roles).toContain('Creación de categoría');
      expect(roles).not.toContain('category.created');
    });

    it('counts the active catalogues and reads the preventive reminders from the server', () => {
      const card = flat('[aria-labelledby="cfg-maint"]');
      expect(card).toContain('Categorías activas2');
      expect(card).toContain('Prioridades activas1');
      expect(card).toContain('Cada 60 min');
      expect(card).toContain('10 MB');
    });

    it('re-checks on demand and disables the button while checking', () => {
      click(Array.from(host().querySelectorAll('button')).find((b) => b.textContent?.includes('Volver a revisar')));
      expect(store.loadHealth).toHaveBeenCalled();
      render(state({ healthLoading: true }));
      expect((Array.from(host().querySelectorAll('button')).find((b) => b.textContent?.includes('Revisando')) as HTMLButtonElement).disabled).toBeTrue();
    });

    it('shows skeletons while loading and an error when it fails', () => {
      render(state({ health: null, healthLoading: true }));
      expect(host().querySelector('[aria-label="Revisando el sistema"]')).not.toBeNull();
      render(state({ health: null, healthError: 'No se pudo leer la salud del sistema.' }));
      expect(host().querySelector('[role="alert"]')!.textContent).toContain('No se pudo leer');
    });

    it('opens and closes the windows with the button and with Escape', () => {
      goTo('Organización');
      expect(host().querySelector('[role="dialog"]')!.textContent).toContain('Organización');
      click(host().querySelector('[role="dialog"] button[aria-label="Cerrar"]'));
      expect(host().querySelector('[role="dialog"]')).toBeNull();
      goTo('Parámetros');
      document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
      fixture.detectChanges();
      expect(host().querySelector('[role="dialog"]')).toBeNull();
    });

    it('never shows secrets in the read-only parameters', () => {
      goTo('Parámetros');
      const text = host().textContent!;
      expect(text).toContain('120 por minuto');
      expect(text).toContain('10 MB');
      expect(text).toContain('cada 60 min');
      expect(text).toContain('La carpeta aún no existe');
      expect(text).not.toMatch(/password|contraseña|sk_|pk_/i);
    });
  });

  describe('categories', () => {
    beforeEach(async () => {
      await create();
      goTo('Categorías');
    });

    it('lists categories with how many requests use each', () => {
      expect(host().textContent).toContain('Impresoras');
      expect(host().textContent).toContain('4 solicitudes');
    });

    it('validates the form and blocks submit until it is valid', () => {
      const submit = button('Añadir') as HTMLButtonElement;
      expect(submit.disabled).toBeTrue();
      type('#cat-name', 'ab');
      type('#cat-code', 'Bad Code');
      (host().querySelector('#cat-name') as HTMLElement).dispatchEvent(new Event('blur'));
      (host().querySelector('#cat-code') as HTMLElement).dispatchEvent(new Event('blur'));
      fixture.detectChanges();
      expect(host().querySelector('#cat-name-err')!.textContent).toContain('al menos 3');
      expect(host().querySelector('#cat-code-err')!.textContent).toContain('caracteres');
      expect(submit.disabled).toBeTrue();
    });

    it('creates a category with a trimmed name', () => {
      type('#cat-name', '  Proyectores ');
      type('#cat-code', 'projectors');
      click(button('Añadir'));
      expect(store.createCategory).toHaveBeenCalledWith({ name: 'Proyectores', code: 'projectors' }, jasmine.any(Function));
    });

    it('does not offer to delete a category that requests use', () => {
      const rows = Array.from(host().querySelectorAll('li'));
      const unused = rows.find((li) => li.textContent?.includes('Impresoras'))!;
      const used = rows.find((li) => li.textContent?.includes('Redes'))!;
      expect(Array.from(unused.querySelectorAll('button')).some((b) => b.textContent?.includes('Eliminar'))).toBeTrue();
      expect(Array.from(used.querySelectorAll('button')).some((b) => b.textContent?.includes('Eliminar'))).toBeFalse();
    });

    it('asks for confirmation before deleting or deactivating', () => {
      click(button('Eliminar'));
      expect(host().querySelector('[role="alertdialog"]')!.textContent).toContain('No se puede deshacer');
      expect(store.deleteCategory).not.toHaveBeenCalled();
      click(button('Volver'));
      expect(host().querySelector('[role="alertdialog"]')).toBeNull();
      click(button('Eliminar'));
      click(button('Confirmar'));
      expect(store.deleteCategory).toHaveBeenCalledWith(categories[0]);
    });

    it('toggles the state after confirming', () => {
      click(Array.from(host().querySelectorAll('button')).filter((b) => b.textContent?.trim() === 'Desactivar')[0]);
      click(button('Confirmar'));
      expect(store.toggleCategory).toHaveBeenCalledWith(categories[0]);
    });

    it('renames with validation', () => {
      click(button('Renombrar'));
      type('input[id^="ren-"]', 'x');
      expect((button('Guardar') as HTMLButtonElement).disabled).toBeTrue();
      type('input[id^="ren-"]', 'Impresión 3D');
      click(button('Guardar'));
      expect(store.renameCategory).toHaveBeenCalledWith(categories[0], 'Impresión 3D', jasmine.any(Function));
    });

    it('shows server field errors and blocks a second submit while saving', () => {
      type('#cat-name', 'Proyectores');
      type('#cat-code', 'projectors');
      render(state({ fieldErrors: { code: 'El formato no es válido.' }, saving: true }));
      expect(host().querySelector('#cat-code-err')!.textContent).toContain('El formato no es válido.');
      expect((button('Guardando') as HTMLButtonElement).disabled).toBeTrue();
    });

    it('shows the empty state', () => {
      render(state({ categories: [] }));
      expect(host().textContent).toContain('Aún no hay categorías');
    });
  });

  describe('priorities', () => {
    beforeEach(async () => {
      await create();
      goTo('Prioridades');
    });

    it('shows the SLA and edits it with validation', () => {
      expect(host().textContent).toContain('resolver en 24 h');
      click(button('Editar'));
      type('#p-sla-2', '0');
      expect(host().textContent).toContain('al menos 1');
      expect((button('Guardar') as HTMLButtonElement).disabled).toBeTrue();
      type('#p-sla-2', '');
      type('#p-sla-2', '48');
      click(button('Guardar'));
      expect(store.updatePriority).toHaveBeenCalledWith(priorities[0], { name: 'Alta', level: 3, sla_hours: 48 }, jasmine.any(Function));
    });

    it('sends null when the deadline is cleared', () => {
      click(button('Editar'));
      type('#p-sla-2', '');
      click(button('Guardar'));
      expect(store.updatePriority.calls.mostRecent().args[1].sla_hours).toBeNull();
    });

    it('asks before deactivating', () => {
      click(button('Desactivar'));
      expect(store.updatePriority).not.toHaveBeenCalled();
      click(button('Confirmar'));
      expect(store.updatePriority).toHaveBeenCalledWith(priorities[0], { is_active: false }, jasmine.any(Function));
    });
  });

  describe('organization', () => {
    beforeEach(async () => {
      await create();
      goTo('Organización');
    });

    const save = () => button('Guardar cambios') as HTMLButtonElement;

    it('says that the defaults are in use until something is saved', () => {
      expect(host().textContent).toContain('Aún no hay un nombre guardado');
      expect((host().querySelector('#org-name') as HTMLInputElement).value).toBe('Mantix');
    });

    it('validates the name and keeps save disabled until it is valid and changed', () => {
      expect(save().disabled).toBeTrue(); // nothing changed yet
      type('#org-name', 'A');
      expect(host().querySelector('#org-name-err')!.textContent).toContain('al menos 2');
      expect(save().disabled).toBeTrue();
      type('#org-name', 'Majesa Café');
      expect(save().disabled).toBeFalse();
    });

    it('asks only for the company name: no legal name or NIT', () => {
      expect(host().querySelector('#org-legal')).toBeNull();
      expect(host().querySelector('#org-nit')).toBeNull();
      expect(host().textContent).not.toContain('NIT');
      expect(host().textContent).not.toContain('Razón social');
    });

    it('saves the trimmed name with single spaces', () => {
      type('#org-name', '  Majesa    Café ');
      click(save());
      expect(store.saveOrganization).toHaveBeenCalledWith({ company_name: 'Majesa Café' });
    });

    it('shows server errors and blocks a second submit while saving', () => {
      type('#org-name', 'Majesa');
      render(state({ fieldErrors: { company_name: 'Debe tener al menos 2 caracteres.' }, saving: true }));
      expect(host().querySelector('#org-name-err')!.textContent).toContain('Debe tener al menos 2 caracteres.');
      expect((button('Guardando') as HTMLButtonElement).disabled).toBeTrue();
    });

    it('loads what was saved and hides the saving form without permission', async () => {
      render(state({ organization: { company_name: 'Majesa', configured: true, updated_at: '2026-10-15T00:00:00Z' } }));
      expect((host().querySelector('#org-name') as HTMLInputElement).value).toBe('Majesa');
      expect(host().textContent).not.toContain('Aún no hay un nombre guardado');
    });
  });

  describe('permissions', () => {
    it('hides every write action without priorities.manage', async () => {
      await create(false);
      goTo('Categorías');
      expect(button('Añadir')).toBeUndefined();
      expect(button('Renombrar')).toBeUndefined();
      goTo('Prioridades');
      expect(button('Editar')).toBeUndefined();
      goTo('Organización');
      expect(button('Guardar cambios')).toBeUndefined();
      expect((host().querySelector('#org-name') as HTMLInputElement).disabled).toBeTrue();
    });
  });

  it('keeps the card buttons legible inside .tw-reset (AA)', fakeAsync(() => {
    create().then(() => undefined);
    flush();
    const buttons = Array.from(host().querySelectorAll('section button, section a[href]'));
    expect(buttons.length).toBeGreaterThanOrEqual(4);
    for (const el of buttons) {
      const style = getComputedStyle(el);
      const background = style.backgroundColor === 'rgba(0, 0, 0, 0)' ? '#ffffff' : flatten(style.backgroundColor, '#ffffff');
      expect(contrastRatio(flatten(style.color), background)).withContext(el.textContent ?? '').toBeGreaterThanOrEqual(WCAG_AA);
    }
  }));
});
