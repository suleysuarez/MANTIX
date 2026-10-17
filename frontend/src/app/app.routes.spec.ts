import { Component } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { Route, Router, provideRouter } from '@angular/router';
import { RouterTestingHarness } from '@angular/router/testing';

import { NON_MENU_ROUTES, routes } from './app.routes';
import { NAV_ITEMS } from './core/nav-items';
import { PendingUsersComponent } from './features/admin/pending-users.component';
import { DashboardComponent } from './features/dashboard/dashboard.component';
import { ForbiddenComponent } from './features/errors/forbidden.component';
import { InventoryComponent } from './features/inventory/inventory.component';
import { MaintenanceHubComponent } from './features/maintenance-hub/maintenance-hub.component';
import { PendingRequestsComponent } from './features/pending-requests/pending-requests.component';
import { ReportsComponent } from './features/reports/reports.component';
import { SettingsComponent } from './features/settings/settings.component';
import { TechniciansComponent } from './features/technicians/technicians.component';
import { TicketsComponent } from './features/tickets/tickets.component';
import { UsersComponent } from './features/users/users.component';

const shell = routes.find((route) => route.path === '' && route.children)!;
const children: Route[] = shell.children!;
const child = (path: string): Route | undefined => children.find((route) => route.path === path);
const load = (route: Route): Promise<{ name: string }> => (route.loadComponent as () => Promise<{ name: string }>)();

/** Entrada del menú → pantalla que debe abrir. Equipos carga sus propias rutas hijas. */
const EXPECTED: Record<string, unknown> = {
  '/dashboard': DashboardComponent,
  '/tickets': TicketsComponent,
  '/solicitudes': PendingRequestsComponent,
  '/technicians': TechniciansComponent,
  '/mantenimiento': MaintenanceHubComponent,
  '/inventario': InventoryComponent,
  '/reportes': ReportsComponent,
  '/usuarios': UsersComponent,
  '/admin/pending-users': PendingUsersComponent,
  '/configuracion': SettingsComponent,
};

@Component({ standalone: true, template: 'destino' })
class TargetComponent {}

describe('application routes', () => {
  it('opens its real screen from every menu entry', async () => {
    for (const item of NAV_ITEMS) {
      const route = child(item.path.slice(1));
      expect(route).withContext(`ruta de «${item.label}» (${item.path})`).toBeDefined();
      if (item.path === '/equipos') {
        const equipment = await (route!.loadChildren as () => Promise<Route[]>)();
        expect(equipment[0].loadComponent).toBeDefined();
        continue;
      }
      expect(route!.loadComponent).withContext(item.label).toBeDefined();
      expect(await load(route!)).withContext(`pantalla de «${item.label}»`).toBe(EXPECTED[item.path] as { name: string });
    }
  });

  it('has no «Próximamente» placeholder left', async () => {
    for (const route of children.filter((entry) => entry.loadComponent)) {
      expect((await load(route)).name).withContext(String(route.path)).not.toMatch(/placeholder/i);
      expect(route.data?.['title']).withContext(String(route.path)).toBeUndefined();
    }
  });

  it('has no orphan routes: each one is a menu entry, a redirect or an explicit non-menu page', () => {
    const menu = NAV_ITEMS.map((item) => item.path.slice(1));
    const orphans = children
      .filter((route) => route.path && !route.redirectTo)
      .map((route) => route.path as string)
      .filter((path) => !menu.includes(path) && !NON_MENU_ROUTES.includes(path));
    expect(orphans).toEqual([]);
  });

  it('protects every menu route with a guard', () => {
    for (const item of NAV_ITEMS) {
      const route = child(item.path.slice(1))!;
      expect(route.canActivate?.length || route.loadChildren).withContext(item.label).toBeTruthy();
    }
  });

  it('lists the old «Mantenimientos» screen nowhere', () => {
    expect(NAV_ITEMS.some((item) => item.label === 'Mantenimientos' || item.path === '/maintenance')).toBeFalse();
    expect(child('maintenance')?.redirectTo).toBe('tickets');
  });

  it('knows the 403 page', async () => {
    expect(await load(child('acceso-denegado')!)).toBe(ForbiddenComponent as unknown as { name: string });
  });

  describe('saved links to the old screen', () => {
    beforeEach(() => {
      const redirects = children.filter((route) => route.redirectTo);
      TestBed.configureTestingModule({ providers: [provideRouter([...redirects, { path: 'tickets', component: TargetComponent }])] });
    });

    it('keeps the query string when /maintenance redirects to tickets', async () => {
      const harness = await RouterTestingHarness.create();
      await harness.navigateByUrl('/maintenance?status=resolved');
      expect(TestBed.inject(Router).url).toBe('/tickets?status=resolved');
    });

    it('opens the ticket from /maintenance/:id', async () => {
      const harness = await RouterTestingHarness.create();
      await harness.navigateByUrl('/maintenance/42');
      expect(TestBed.inject(Router).url).toBe('/tickets?ticket=42');
    });
  });
});
