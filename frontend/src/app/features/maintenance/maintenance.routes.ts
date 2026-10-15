import { Routes } from '@angular/router';

export const MAINTENANCE_ROUTES: Routes = [
  {
    path: '',
    loadComponent: () => import('./maintenance-list.component').then((m) => m.MaintenanceListComponent),
  },
  {
    path: ':id',
    loadComponent: () => import('./maintenance-detail.component').then((m) => m.MaintenanceDetailComponent),
  },
];
