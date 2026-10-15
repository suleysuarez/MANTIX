import { Routes } from '@angular/router';

import { authGuard, authorizedGuard, permissionGuard, roleGuard } from './core/auth.guard';
import { LoadErrorComponent } from './features/errors/load-error.component';

/** Rutas del shell que no son entradas del menú (el test de rutas las exige explícitas). */
export const NON_MENU_ROUTES: readonly string[] = ['cuenta', 'acceso-denegado'];

export const routes: Routes = [
  { path: 'auth', loadChildren: () => import('./features/auth/auth.routes').then((m) => m.AUTH_ROUTES) },
  { path: 'error-carga', component: LoadErrorComponent },
  {
    path: '',
    canActivate: [authGuard],
    loadComponent: () => import('./layout/app-shell.component').then((m) => m.AppShellComponent),
    children: [
      { path: '', redirectTo: 'dashboard', pathMatch: 'full' },
      { path: 'dashboard', canActivate: [authorizedGuard], loadComponent: () => import('./features/dashboard/dashboard.component').then((m) => m.DashboardComponent) },
      { path: 'cuenta', canActivate: [authorizedGuard], loadComponent: () => import('./features/account/account.component').then((m) => m.AccountComponent) },
      { path: 'acceso-denegado', canActivate: [authorizedGuard], loadComponent: () => import('./features/errors/forbidden.component').then((m) => m.ForbiddenComponent) },
      { path: 'admin/pending-users', canActivate: [permissionGuard('users.manage')], loadComponent: () => import('./features/admin/pending-users.component').then((m) => m.PendingUsersComponent) },
      { path: 'equipos', loadChildren: () => import('./features/equipos/equipos.routes').then((m) => m.EQUIPOS_ROUTES) },
      { path: 'tickets', canActivate: [permissionGuard('maintenance.read')], loadComponent: () => import('./features/tickets/tickets.component').then((m) => m.TicketsComponent) },
      { path: 'solicitudes', canActivate: [roleGuard('maintenance.manage', 'ADMIN', 'SUPERVISOR')], loadComponent: () => import('./features/pending-requests/pending-requests.component').then((m) => m.PendingRequestsComponent) },
      { path: 'technicians', canActivate: [permissionGuard('maintenance.read')], loadComponent: () => import('./features/technicians/technicians.component').then((m) => m.TechniciansComponent) },
      { path: 'mantenimiento', canActivate: [permissionGuard('maintenance.read')], loadComponent: () => import('./features/maintenance-hub/maintenance-hub.component').then((m) => m.MaintenanceHubComponent) },
      { path: 'inventario', canActivate: [permissionGuard('inventory.read')], loadComponent: () => import('./features/inventory/inventory.component').then((m) => m.InventoryComponent) },
      { path: 'reportes', canActivate: [permissionGuard('reports.read')], loadComponent: () => import('./features/reports/reports.component').then((m) => m.ReportsComponent) },
      { path: 'configuracion', canActivate: [permissionGuard('users.manage')], loadComponent: () => import('./features/settings/settings.component').then((m) => m.SettingsComponent) },
      // Pantalla antigua «Mantenimientos»: era la lista y el detalle de solicitudes, que ahora es Tickets.
      // Se conservan los enlaces guardados; los parámetros de la consulta (?status=, ?equipmentId=) pasan solos.
      { path: 'maintenance', pathMatch: 'full', redirectTo: 'tickets' },
      { path: 'maintenance/:id', redirectTo: ({ params }) => `/tickets?ticket=${encodeURIComponent(params['id'])}` },
    ],
  },
  { path: '**', redirectTo: 'dashboard' },
];
