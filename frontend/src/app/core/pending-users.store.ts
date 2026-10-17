import { Injectable, inject } from '@angular/core';
import { BehaviorSubject, Observable, forkJoin } from 'rxjs';

import { apiErrorMessage } from './api-errors';
import { ToastService } from './toast.service';
import { AdminRole, AdminUsersService, PendingUser } from './admin-users.service';

export interface PendingUsersState {
  users: PendingUser[];
  roles: AdminRole[];
  loading: boolean;
  savingUserId: number | null;
  error: string;
}

const INITIAL_STATE: PendingUsersState = {
  users: [],
  roles: [],
  loading: true,
  savingUserId: null,
  error: '',
};

/** Observer pattern store for the pending-authorization queue. */
@Injectable({ providedIn: 'root' })
export class PendingUsersStore {
  private readonly api = inject(AdminUsersService);
  private readonly toasts = inject(ToastService);
  private readonly subject = new BehaviorSubject<PendingUsersState>(INITIAL_STATE);

  readonly state$: Observable<PendingUsersState> = this.subject.asObservable();

  load(): void {
    this.patch({ loading: true, error: '' });
    forkJoin({ users: this.api.listPendingUsers(), roles: this.api.listRoles() }).subscribe({
      next: ({ users, roles }) => this.patch({ users, roles, loading: false }),
      error: (error) =>
        this.patch({ loading: false, error: apiErrorMessage(error, 'No se pudieron cargar los usuarios pendientes.') }),
    });
  }

  assignRoles(userId: number, roleIds: number[]): void {
    this.patch({ savingUserId: userId, error: '' });
    this.api.assignRoles(userId, roleIds).subscribe({
      next: () => {
        const person = this.subject.value.users.find((user) => user.id === userId);
        this.patch({ users: this.subject.value.users.filter((user) => user.id !== userId), savingUserId: null });
        this.toasts.success(person ? `${person.full_name} ya puede usar Mantix.` : 'Roles asignados.');
      },
      error: (error) => {
        this.patch({ savingUserId: null });
        this.toasts.error(apiErrorMessage(error, 'No se pudieron asignar los roles. Inténtalo de nuevo.'));
      },
    });
  }

  private patch(partial: Partial<PendingUsersState>): void {
    this.subject.next({ ...this.subject.value, ...partial });
  }
}
