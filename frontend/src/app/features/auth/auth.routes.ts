import { Routes } from '@angular/router';

import { authGuard } from '../../core/auth.guard';

export const AUTH_ROUTES: Routes = [
  { path: 'login', loadComponent: () => import('./login.component').then((m) => m.LoginComponent) },
  { path: 'pending', canActivate: [authGuard], loadComponent: () => import('./pending.component').then((m) => m.PendingComponent) },
];
