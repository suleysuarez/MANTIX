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
          <span class="material-symbols-outlined" aria-hidden="true">notifications</span>
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
     .bell-button { position: relative; display: flex; align-items: center; justify-content: center; width: 36px; height: 36px; background: linear-gradient(135deg, #add7f6, #a2d2ff); border: 0; border-radius: 12px; color: #3e5c76; cursor: pointer; transition: all .25s ease; }
     .bell-button:hover { transform: translateY(-2px); box-shadow: 0 10px 20px rgba(162, 210, 255, .25); }
     .bell-button:focus-visible { outline: 2px solid #3e5c76; outline-offset: 2px; }
     .bell-button .material-symbols-outlined { font-size: 20px; }
     .badge { position: absolute; top: -.3rem; right: -.3rem; min-width: 1rem; padding: 0 .25rem; border-radius: 999px; background: #d4a017; color: #fff; font-weight: 700; font-size: .6rem; line-height: 1rem; text-align: center; }
     .panel { position: absolute; right: 0; top: calc(100% + .6rem); width: min(92vw, 360px); max-height: 420px; overflow: auto; background: #fff; color: #3e5c76; border: 1px solid rgba(62, 92, 118, .08); border-radius: 16px; box-shadow: 0 12px 32px rgba(62, 92, 118, .16); z-index: 20; }
     .panel header { display: flex; justify-content: space-between; align-items: center; padding: .75rem 1rem; border-bottom: 1px solid #ced4da; }
     .link { background: none; border: 0; color: #3e5c76; font-weight: 600; cursor: pointer; font-size: .85rem; }
     .link:disabled { color: #778da9; opacity: .6; cursor: default; }
     ul { list-style: none; margin: 0; padding: 0; }
     li button { display: grid; gap: .15rem; width: 100%; text-align: left; background: #fff; border: 0; border-bottom: 1px solid rgba(206, 212, 218, .6); padding: .75rem 1rem; cursor: pointer; transition: background .25s ease; }
     li button:hover { background: rgba(173, 215, 246, .2); }
     li.unread button { background: rgba(173, 215, 246, .35); }
     .title { font-weight: 600; } .message { color: #778da9; font-size: .9rem; } time { color: #778da9; opacity: .8; font-size: .75rem; }
     .empty, .error { padding: 1rem; margin: 0; color: #778da9; } .error { color: #3e5c76; font-weight: 600; }`,
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
