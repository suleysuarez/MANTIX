import { Routes } from '@angular/router';

import { permissionGuard } from '../../core/auth.guard';

export const EQUIPOS_ROUTES: Routes = [
  {
    path: '',
    canActivate: [permissionGuard('equipos:ver')],
    loadComponent: () =>
      import('./equipment-list.component').then((m) => m.EquipmentListComponent),
  },
];
