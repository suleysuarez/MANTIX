import { Routes } from '@angular/router';

import { authGuard, authorizedGuard, permissionGuard, roleGuard } from './core/auth.guard';

export const routes: Routes = [
  { path: 'auth', loadChildren: () => import('./features/auth/auth.routes').then((m) => m.AUTH_ROUTES) },
  {
    path: '',
    canActivate: [authGuard],
    loadComponent: () => import('./layout/app-shell.component').then((m) => m.AppShellComponent),
    children: [
      { path: '', redirectTo: 'dashboard', pathMatch: 'full' },
      { path: 'dashboard', canActivate: [authorizedGuard], loadComponent: () => import('./features/dashboard/dashboard.component').then((m) => m.DashboardComponent) },
      { path: 'cuenta', canActivate: [authorizedGuard], loadComponent: () => import('./features/account/account.component').then((m) => m.AccountComponent) },
      { path: 'admin/pending-users', canActivate: [permissionGuard('users.manage')], loadComponent: () => import('./features/admin/pending-users.component').then((m) => m.PendingUsersComponent) },
      { path: 'maintenance', canActivate: [permissionGuard('maintenance.read')], loadChildren: () => import('./features/maintenance/maintenance.routes').then((m) => m.MAINTENANCE_ROUTES) },
      { path: 'solicitudes', canActivate: [roleGuard('maintenance.manage', 'ADMIN', 'SUPERVISOR')], loadComponent: () => import('./features/pending-requests/pending-requests.component').then((m) => m.PendingRequestsComponent) },
      { path: 'mantenimiento', canActivate: [permissionGuard('maintenance.read')], loadComponent: () => import('./features/maintenance-hub/maintenance-hub.component').then((m) => m.MaintenanceHubComponent) },
      { path: 'technicians', canActivate: [permissionGuard('maintenance.read')], loadComponent: () => import('./features/technicians/technicians.component').then((m) => m.TechniciansComponent) },
      { path: 'tickets', canActivate: [permissionGuard('maintenance.read')], data: { title: 'Tickets', icon: 'confirmation_number', description: 'Seguimiento de incidentes reportados por los usuarios.' }, loadComponent: () => import('./features/placeholder/module-placeholder.component').then((m) => m.ModulePlaceholderComponent) },
      { path: 'inventario', canActivate: [permissionGuard('inventory.read')], loadComponent: () => import('./features/inventory/inventory.component').then((m) => m.InventoryComponent) },
      { path: 'reportes', canActivate: [permissionGuard('reports.read')], loadComponent: () => import('./features/reports/reports.component').then((m) => m.ReportsComponent) },
      { path: 'configuracion', canActivate: [permissionGuard('users.manage')], loadComponent: () => import('./features/settings/settings.component').then((m) => m.SettingsComponent) },
      { path: 'equipos', loadChildren: () => import('./features/equipos/equipos.routes').then((m) => m.EQUIPOS_ROUTES) },
    ],
  },
  { path: '**', redirectTo: 'dashboard' },
];
