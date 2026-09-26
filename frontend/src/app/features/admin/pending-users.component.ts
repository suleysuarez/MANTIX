import {
  ChangeDetectionStrategy,
  Component,
  OnInit,
  inject,
} from '@angular/core';

import {
  AdminRole,
  AdminUsersService,
  PendingUser,
} from '../../core/admin-users.service';

@Component({
  standalone: true,
  template: `
    <main class="admin-page">
      <header>
        <div>
          <p class="eyebrow">Administration</p>
          <h1>Pending authorization</h1>
          <p>Assign one or more local application roles to authenticated users.</p>
        </div>
      </header>

      @if (error) {
        <p class="error" role="alert">{{ error }}</p>
      }
      @if (loading) {
        <p>Loading pending users…</p>
      } @else if (pendingUsers.length === 0) {
        <section class="empty-card">There are no active users waiting for authorization.</section>
      } @else {
        <section class="user-list">
          @for (user of pendingUsers; track user.id) {
            <article class="user-card">
              <div>
                <h2>{{ user.full_name }}</h2>
                <p>{{ user.email }}</p>
              </div>
              <fieldset>
                <legend>Roles</legend>
                @for (role of roles; track role.id) {
                  <label>
                    <input
                      type="checkbox"
                      [checked]="hasSelectedRole(user.id, role.id)"
                      (change)="toggleRole(user.id, role.id, $any($event.target).checked)"
                    />
                    {{ role.name }} ({{ role.code }})
                  </label>
                }
              </fieldset>
              <button
                type="button"
                [disabled]="savingUserId === user.id || !selectedRoles(user.id).length"
                (click)="assignRoles(user)"
              >
                {{ savingUserId === user.id ? 'Assigning…' : 'Assign roles' }}
              </button>
            </article>
          }
        </section>
      }
    </main>
  `,
  styles: [
    `.admin-page { max-width: 960px; margin: 3rem auto; padding: 0 1.5rem; }
     .eyebrow { color: #2563eb; font-weight: 700; text-transform: uppercase; letter-spacing: .08em; }
     .user-list { display: grid; gap: 1rem; }
     .user-card, .empty-card { padding: 1.5rem; background: white; border: 1px solid #e2e8f0; border-radius: 10px; }
     .user-card { display: grid; gap: 1rem; }
     h2, p { margin: 0; } fieldset { border: 0; padding: 0; display: flex; flex-wrap: wrap; gap: .8rem 1.2rem; }
     label { display: flex; gap: .4rem; align-items: center; }
     button { width: fit-content; padding: .65rem 1rem; border: 0; border-radius: 6px; background: #0f172a; color: white; cursor: pointer; }
     button:disabled { cursor: not-allowed; opacity: .5; } .error { color: #b91c1c; }`,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class PendingUsersComponent implements OnInit {
  private readonly adminUsers = inject(AdminUsersService);
  pendingUsers: PendingUser[] = [];
  roles: AdminRole[] = [];
  loading = true;
  error = '';
  savingUserId: number | null = null;
  private readonly selections = new Map<number, Set<number>>();

  async ngOnInit(): Promise<void> {
    await this.load();
  }

  hasSelectedRole(userId: number, roleId: number): boolean {
    return this.selections.get(userId)?.has(roleId) ?? false;
  }

  selectedRoles(userId: number): number[] {
    return [...(this.selections.get(userId) ?? new Set<number>())];
  }

  toggleRole(userId: number, roleId: number, checked: boolean): void {
    const selection = this.selections.get(userId) ?? new Set<number>();
    checked ? selection.add(roleId) : selection.delete(roleId);
    this.selections.set(userId, selection);
  }

  async assignRoles(user: PendingUser): Promise<void> {
    this.savingUserId = user.id;
    this.error = '';
    try {
      await this.adminUsers.assignRoles(user.id, this.selectedRoles(user.id));
      this.pendingUsers = this.pendingUsers.filter((item) => item.id !== user.id);
      this.selections.delete(user.id);
    } catch {
      this.error = 'The roles could not be assigned. Please try again.';
    } finally {
      this.savingUserId = null;
    }
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.error = '';
    try {
      [this.pendingUsers, this.roles] = await Promise.all([
        this.adminUsers.listPendingUsers(),
        this.adminUsers.listRoles(),
      ]);
    } catch {
      this.error = 'Pending users could not be loaded.';
    } finally {
      this.loading = false;
    }
  }
}
