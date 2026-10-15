import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { BehaviorSubject } from 'rxjs';

import { DashboardState, DashboardStore } from '../../core/dashboard.store';
import { LocalProfileService } from '../../core/local-profile.service';
import { PermissionsService } from '../../core/permissions.service';
import { DashboardComponent } from './dashboard.component';

const summary = {
  scope: 'own' as const,
  window_days: 30,
  tickets: {
    total: 5,
    open: 3,
    overdue: 1,
    by_status: [{ key: 'submitted', count: 2 }, { key: 'in_progress', count: 1 }, { key: 'closed', count: 2 }],
    open_by_priority: [{ key: 'high', count: 1 }, { key: 'low', count: 2 }],
  },
};

const state = (over: Partial<DashboardState> = {}): DashboardState => ({
  loading: false, period: '30d', mode: 'global', mine: null, kpis: null, trends: null, alerts: null, topEquipment: null, technicians: null,
  ...over,
});

describe('Dashboard by permission (same screen, sections per role)', () => {
  let load: jasmine.Spy;

  async function render(granted: string[], initial: DashboardState) {
    load = jasmine.createSpy('load');
    TestBed.configureTestingModule({
      providers: [
        provideRouter([]),
        { provide: DashboardStore, useValue: { state$: new BehaviorSubject(initial).asObservable(), load } },
        { provide: LocalProfileService, useValue: { getProfile: () => Promise.resolve({ full_name: 'Ana' }) } },
        { provide: PermissionsService, useValue: { load: () => Promise.resolve(), has: (code: string) => granted.includes(code) } },
      ],
    });
    const fixture = TestBed.createComponent(DashboardComponent);
    document.body.appendChild(fixture.nativeElement);
    fixture.detectChanges();
    await fixture.whenStable();
    fixture.detectChanges();
    return fixture.nativeElement as HTMLElement;
  }
  const text = (root: HTMLElement) => root.textContent!.replace(/\s+/g, ' ');

  afterEach(() => document.querySelectorAll('app-dashboard').forEach((el) => el.remove()));

  it('a requester gets the state of their own requests and none of the operation', async () => {
    const root = await render(['dashboard:ver', 'tickets:ver'], state({ mode: 'requester', mine: summary }));

    expect(load).toHaveBeenCalledWith(undefined, 'requester');
    expect(text(root)).toContain('Mis solicitudes por estado');
    expect(text(root)).toContain('5 en total · 3 abiertas · 1 fuera de plazo');
    expect(text(root)).toContain('Enviado');
    expect(text(root)).toContain('Abiertas por prioridad');
    expect(text(root)).not.toContain('Equipos con más incidencias');
    expect(text(root)).not.toContain('Rendimiento del equipo técnico');
    expect(root.querySelector('[aria-label="Indicadores clave"]')).toBeNull();
    expect(root.querySelector('a[href="/tickets"]')).not.toBeNull();
  });

  it('a requester without requests is told how it works instead of seeing an empty box', async () => {
    const empty = { ...summary, tickets: { ...summary.tickets, total: 0, open: 0, overdue: 0, by_status: [], open_by_priority: [] } };
    const root = await render(['dashboard:ver'], state({ mode: 'requester', mine: empty }));
    expect(text(root)).toContain('Aún no has creado solicitudes');
    expect(text(root)).toContain('No tienes solicitudes abiertas');
  });

  it('a requester whose numbers fail to load can retry', async () => {
    const root = await render(['dashboard:ver'], state({ mode: 'requester', mine: null }));
    expect(text(root)).toContain('No se pudo cargar el estado de tus solicitudes');
    expect(root.querySelector('[role="alert"] button')).not.toBeNull();
  });

  it('a technician sees their own load and performance, but not the ranking of equipment', async () => {
    const root = await render(['dashboard:ver', 'tickets:ver_asignados'], state({ mode: 'technician' }));

    expect(load).toHaveBeenCalledWith(undefined, 'technician');
    expect(root.querySelector('[aria-label="Indicadores clave"]')).not.toBeNull();
    expect(text(root)).toContain('Mi carga y mi rendimiento');
    expect(text(root)).not.toContain('Equipos con más incidencias');
    expect(text(root)).not.toContain('Mis solicitudes por estado');
  });

  it('a supervisor or administrator sees the whole operation', async () => {
    const root = await render(['dashboard:ver', 'dashboard:ver_todos', 'tickets:ver_asignados'], state({ mode: 'global' }));

    expect(load).toHaveBeenCalledWith(undefined, 'global');
    expect(root.querySelector('[aria-label="Indicadores clave"]')).not.toBeNull();
    expect(text(root)).toContain('Equipos con más incidencias');
    expect(text(root)).toContain('Rendimiento del equipo técnico');
    expect(text(root)).not.toContain('Mis solicitudes por estado');
  });

  it('decides by permission, not by role name: the widest permission wins', async () => {
    await render(['dashboard:ver', 'dashboard:ver_todos'], state({ mode: 'global' }));
    expect(load).toHaveBeenCalledWith(undefined, 'global');
  });
});
