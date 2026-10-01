import { Injectable, inject } from '@angular/core';
import { BehaviorSubject, Observable } from 'rxjs';

import { httpErrorMessage } from './http-error';
import { AppNotification, NotificationsService } from './notifications.service';

export interface NotificationsState {
  items: AppNotification[];
  unreadCount: number;
  loading: boolean;
  error: string;
}

const INITIAL_STATE: NotificationsState = { items: [], unreadCount: 0, loading: false, error: '' };

/** Observer pattern store for the signed-in user's in-app notifications. */
@Injectable({ providedIn: 'root' })
export class NotificationsStore {
  private readonly api = inject(NotificationsService);
  private readonly subject = new BehaviorSubject<NotificationsState>(INITIAL_STATE);

  readonly state$: Observable<NotificationsState> = this.subject.asObservable();

  load(): void {
    this.patch({ loading: true });
    this.api.list().subscribe({
      next: (list) =>
        this.patch({ items: list.items, unreadCount: list.unread_count, loading: false, error: '' }),
      // Un fallo de sondeo no debe borrar lo que el usuario ya ve.
      error: (error) =>
        this.patch({ loading: false, error: httpErrorMessage(error, 'Notifications could not be loaded.') }),
    });
  }

  markRead(id: number): void {
    const target = this.subject.value.items.find((item) => item.id === id);
    if (!target || target.is_read) {
      return;
    }
    this.api.markRead(id).subscribe({
      next: (updated) =>
        this.patch({
          items: this.subject.value.items.map((item) => (item.id === id ? updated : item)),
          unreadCount: Math.max(0, this.subject.value.unreadCount - 1),
        }),
      error: () => this.patch({ error: 'The notification could not be updated.' }),
    });
  }

  markAllRead(): void {
    this.api.markAllRead().subscribe({
      next: () =>
        this.patch({
          items: this.subject.value.items.map((item) => ({ ...item, is_read: true })),
          unreadCount: 0,
        }),
      error: () => this.patch({ error: 'The notifications could not be updated.' }),
    });
  }

  /** Descarta el estado al cerrar sesión o cambiar de usuario. */
  clear(): void {
    this.subject.next(INITIAL_STATE);
  }

  private patch(partial: Partial<NotificationsState>): void {
    this.subject.next({ ...this.subject.value, ...partial });
  }
}
