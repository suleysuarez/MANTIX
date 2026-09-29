import { AsyncPipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, OnInit, inject } from '@angular/core';

import { PendingUsersStore } from '../../core/pending-users.store';
import { PendingUserCardComponent } from './pending-user-card.component';

/** Smart (container) component: talks to the store, delegates rendering. */
@Component({
  standalone: true,
  imports: [AsyncPipe, PendingUserCardComponent],
  template: `
    @if (state$ | async; as state) {
      <main class="admin-page">
        <header>
          <div>
            <p class="eyebrow">Administration</p>
            <h1>Pending authorization</h1>
            <p>Assign one or more local application roles to authenticated users.</p>
          </div>
        </header>

        @if (state.error) {
          <p class="error" role="alert">{{ state.error }}</p>
        }
        @if (state.loading) {
          <p>Loading pending users…</p>
        } @else if (state.users.length === 0) {
          <section class="empty-card">There are no active users waiting for authorization.</section>
        } @else {
          <section class="user-list">
            @for (user of state.users; track user.id) {
              <app-pending-user-card
                [user]="user"
                [roles]="state.roles"
                [saving]="state.savingUserId === user.id"
                (assign)="assignRoles(user.id, $event)"
              />
            }
          </section>
        }
      </main>
    }
  `,
  styles: [
    `.admin-page { max-width: 960px; margin: 3rem auto; padding: 0 1.5rem; }
     .eyebrow { color: #2563eb; font-weight: 700; text-transform: uppercase; letter-spacing: .08em; }
     .user-list { display: grid; gap: 1rem; }
     .empty-card { padding: 1.5rem; background: white; border: 1px solid #e2e8f0; border-radius: 10px; }
     .error { color: #b91c1c; }`,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class PendingUsersComponent implements OnInit {
  private readonly store = inject(PendingUsersStore);

  readonly state$ = this.store.state$;

  ngOnInit(): void {
    this.store.load();
  }

  assignRoles(userId: number, roleIds: number[]): void {
    this.store.assignRoles(userId, roleIds);
  }
}
