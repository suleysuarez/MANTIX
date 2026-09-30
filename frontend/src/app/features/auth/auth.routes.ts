import { Routes } from '@angular/router';

import { authGuard, guestGuard } from '../../core/auth.guard';

export const AUTH_ROUTES: Routes = [
  { path: 'login', canActivate: [guestGuard], loadComponent: () => import('./login.component').then((m) => m.LoginComponent) },
  { path: 'sign-up', canActivate: [guestGuard], loadComponent: () => import('./sign-up.component').then((m) => m.SignUpComponent) },
  { path: 'pending', canActivate: [authGuard], loadComponent: () => import('./pending.component').then((m) => m.PendingComponent) },
];
