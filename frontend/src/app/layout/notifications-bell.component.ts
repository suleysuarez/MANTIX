import { AsyncPipe, DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, DestroyRef, OnInit, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { Router } from '@angular/router';
import { timer } from 'rxjs';

import { AppNotification } from '../core/notifications.service';
import { NotificationsStore } from '../core/notifications.store';

const POLL_INTERVAL_MS = 60_000;

/** Smart component: campana con contador y lista desplegable de notificaciones. */
@Component({
  selector: 'app-notifications-bell',
  standalone: true,
  imports: [AsyncPipe, DatePipe],
  template: `
    @if (state$ | async; as state) {
      <div class="bell">
        <button
          type="button"
          class="bell-button"
          aria-label="Notifications"
          [attr.aria-expanded]="open()"
          (click)="open.set(!open())">
          <span aria-hidden="true">🔔</span>
          @if (state.unreadCount > 0) {
            <span class="badge" aria-live="polite">{{ state.unreadCount }}</span>
          }
        </button>

        @if (open()) {
          <section class="panel" aria-label="Notifications list">
            <header>
              <strong>Notifications</strong>
              <button type="button" class="link" [disabled]="state.unreadCount === 0" (click)="markAll()">
                Mark all as read
              </button>
            </header>
            @if (state.error) {
              <p class="error" role="alert">{{ state.error }}</p>
            }
            @if (state.items.length === 0) {
              <p class="empty">You have no notifications.</p>
            } @else {
              <ul>
                @for (item of state.items; track item.id) {
                  <li [class.unread]="!item.is_read">
                    <button type="button" (click)="select(item)">
                      <span class="title">{{ item.title }}</span>
                      <span class="message">{{ item.message }}</span>
                      <time>{{ item.created_at | date: 'short' }}</time>
                    </button>
                  </li>
                }
              </ul>
            }
          </section>
        }
      </div>
    }
  `,
  styles: [
    `.bell { position: relative; }
     .bell-button { position: relative; background: transparent; border: 0; color: inherit; font-size: 1.2rem; cursor: pointer; padding: .3rem .5rem; }
     .badge { position: absolute; top: -.1rem; right: -.1rem; min-width: 1.1rem; padding: 0 .25rem; border-radius: 999px; background: #ef4444; color: white; font-size: .7rem; line-height: 1.1rem; text-align: center; }
     .panel { position: absolute; right: 0; top: 2.4rem; width: min(92vw, 360px); max-height: 420px; overflow: auto; background: white; color: #0f172a; border: 1px solid #e2e8f0; border-radius: 10px; box-shadow: 0 10px 30px #0f172a33; z-index: 20; }
     .panel header { display: flex; justify-content: space-between; align-items: center; padding: .75rem 1rem; border-bottom: 1px solid #e2e8f0; }
     .link { background: none; border: 0; color: #2563eb; cursor: pointer; font-size: .85rem; }
     .link:disabled { color: #94a3b8; cursor: default; }
     ul { list-style: none; margin: 0; padding: 0; }
     li button { display: grid; gap: .15rem; width: 100%; text-align: left; background: white; border: 0; border-bottom: 1px solid #f1f5f9; padding: .75rem 1rem; cursor: pointer; }
     li.unread button { background: #eff6ff; }
     .title { font-weight: 600; } .message { color: #475569; font-size: .9rem; } time { color: #94a3b8; font-size: .75rem; }
     .empty, .error { padding: 1rem; margin: 0; } .error { color: #b91c1c; }`,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class NotificationsBellComponent implements OnInit {
  private readonly store = inject(NotificationsStore);
  private readonly router = inject(Router);
  private readonly destroyRef = inject(DestroyRef);

  readonly state$ = this.store.state$;
  readonly open = signal(false);

  ngOnInit(): void {
    timer(0, POLL_INTERVAL_MS).pipe(takeUntilDestroyed(this.destroyRef)).subscribe(() => this.store.load());
  }

  select(item: AppNotification): void {
    this.store.markRead(item.id);
    this.open.set(false);
    if (item.link_url?.startsWith('/')) {
      void this.router.navigateByUrl(item.link_url);
    }
  }

  markAll(): void {
    this.store.markAllRead();
  }
}
