import { Routes } from '@angular/router';

import { authorizedGuard, permissionGuard } from './core/auth.guard';

export const routes: Routes = [
  { path: '', redirectTo: 'dashboard', pathMatch: 'full' },
  { path: 'dashboard', canActivate: [authorizedGuard], loadComponent: () => import('./features/dashboard/dashboard.component').then((m) => m.DashboardComponent) },
  { path: 'admin/pending-users', canActivate: [permissionGuard('users.manage')], loadComponent: () => import('./features/admin/pending-users.component').then((m) => m.PendingUsersComponent) },
  { path: 'auth', loadChildren: () => import('./features/auth/auth.routes').then((m) => m.AUTH_ROUTES) },
  { path: 'equipos', loadChildren: () => import('./features/equipos/equipos.routes').then((m) => m.EQUIPOS_ROUTES) },
  { path: '**', redirectTo: 'dashboard' },
];
