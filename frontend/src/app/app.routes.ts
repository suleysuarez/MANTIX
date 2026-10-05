import { Routes } from '@angular/router';

import { authGuard, authorizedGuard, permissionGuard } from './core/auth.guard';

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
      { path: 'technicians', canActivate: [permissionGuard('maintenance.read')], loadComponent: () => import('./features/maintenance/technicians.component').then((m) => m.TechniciansComponent) },
      { path: 'tickets', canActivate: [permissionGuard('maintenance.read')], data: { title: 'Tickets', icon: 'confirmation_number', description: 'Seguimiento de incidentes reportados por los usuarios.' }, loadComponent: () => import('./features/placeholder/module-placeholder.component').then((m) => m.ModulePlaceholderComponent) },
      { path: 'inventario', canActivate: [permissionGuard('equipment.read')], data: { title: 'Inventario', icon: 'inventory_2', description: 'Control de existencias y repuestos del parque tecnológico.' }, loadComponent: () => import('./features/placeholder/module-placeholder.component').then((m) => m.ModulePlaceholderComponent) },
      { path: 'reportes', canActivate: [permissionGuard('maintenance.read')], data: { title: 'Reportes', icon: 'monitoring', description: 'Indicadores y reportes de mantenimiento.' }, loadComponent: () => import('./features/placeholder/module-placeholder.component').then((m) => m.ModulePlaceholderComponent) },
      { path: 'configuracion', canActivate: [permissionGuard('users.manage')], data: { title: 'Configuración', icon: 'settings', description: 'Parámetros generales del sistema.' }, loadComponent: () => import('./features/placeholder/module-placeholder.component').then((m) => m.ModulePlaceholderComponent) },
      { path: 'equipos', loadChildren: () => import('./features/equipos/equipos.routes').then((m) => m.EQUIPOS_ROUTES) },
    ],
  },
  { path: '**', redirectTo: 'dashboard' },
];
