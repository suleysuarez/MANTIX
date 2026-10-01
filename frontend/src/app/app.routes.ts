import { Routes } from '@angular/router';

import { authorizedGuard, permissionGuard } from './core/auth.guard';

export const routes: Routes = [
  { path: 'auth', loadChildren: () => import('./features/auth/auth.routes').then((m) => m.AUTH_ROUTES) },
  {
    path: '',
    loadComponent: () => import('./layout/app-shell.component').then((m) => m.AppShellComponent),
    children: [
      { path: '', redirectTo: 'dashboard', pathMatch: 'full' },
      { path: 'dashboard', canActivate: [authorizedGuard], loadComponent: () => import('./features/dashboard/dashboard.component').then((m) => m.DashboardComponent) },
      { path: 'admin/pending-users', canActivate: [permissionGuard('users.manage')], loadComponent: () => import('./features/admin/pending-users.component').then((m) => m.PendingUsersComponent) },
      { path: 'maintenance', canActivate: [permissionGuard('maintenance.read')], loadChildren: () => import('./features/maintenance/maintenance.routes').then((m) => m.MAINTENANCE_ROUTES) },
      { path: 'technicians', canActivate: [permissionGuard('maintenance.read')], loadComponent: () => import('./features/maintenance/technicians.component').then((m) => m.TechniciansComponent) },
      { path: 'equipos', loadChildren: () => import('./features/equipos/equipos.routes').then((m) => m.EQUIPOS_ROUTES) },
    ],
  },
  { path: '**', redirectTo: 'dashboard' },
];
