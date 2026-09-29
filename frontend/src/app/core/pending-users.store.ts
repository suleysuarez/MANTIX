import { Injectable, inject } from '@angular/core';
import { BehaviorSubject, Observable, forkJoin } from 'rxjs';

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
  private readonly subject = new BehaviorSubject<PendingUsersState>(INITIAL_STATE);

  readonly state$: Observable<PendingUsersState> = this.subject.asObservable();

  load(): void {
    this.patch({ loading: true, error: '' });
    forkJoin({ users: this.api.listPendingUsers(), roles: this.api.listRoles() }).subscribe({
      next: ({ users, roles }) => this.patch({ users, roles, loading: false }),
      error: () => this.patch({ loading: false, error: 'Pending users could not be loaded.' }),
    });
  }

  assignRoles(userId: number, roleIds: number[]): void {
    this.patch({ savingUserId: userId, error: '' });
    this.api.assignRoles(userId, roleIds).subscribe({
      next: () =>
        this.patch({
          users: this.subject.value.users.filter((user) => user.id !== userId),
          savingUserId: null,
        }),
      error: () =>
        this.patch({
          savingUserId: null,
          error: 'The roles could not be assigned. Please try again.',
        }),
    });
  }

  private patch(partial: Partial<PendingUsersState>): void {
    this.subject.next({ ...this.subject.value, ...partial });
  }
}
