import { Routes } from '@angular/router';

export const routes: Routes = [
  { path: '', redirectTo: 'dashboard', pathMatch: 'full' },
  { path: 'dashboard', loadComponent: () => import('./features/dashboard/dashboard.component').then((m) => m.DashboardComponent) },
  { path: 'auth', loadChildren: () => import('./features/auth/auth.routes').then((m) => m.AUTH_ROUTES) },
  { path: 'equipos', loadChildren: () => import('./features/equipos/equipos.routes').then((m) => m.EQUIPOS_ROUTES) },
  { path: '**', redirectTo: 'dashboard' },
];
