import { ChangeDetectionStrategy, Component, inject } from '@angular/core';

import { ClerkService } from '../../core/clerk.service';

@Component({
  selector: 'app-pending',
  standalone: true,
  template: `
    <main class="pending-page">
      <section class="pending-card">
        <h1>Account created successfully</h1>
        <p>
          Your account is authenticated, but an administrator must assign an application role
          before you can access the maintenance workspace.
        </p>
        <button type="button" (click)="signOut()">Sign out</button>
      </section>
    </main>
  `,
  styles: [
    `.pending-page { min-height: 100vh; display: grid; place-items: center; background: #f1f5f9; }
     .pending-card { width: min(92vw, 560px); padding: 2.5rem; background: white; border-radius: 12px; box-shadow: 0 10px 30px #0f172a1a; }
     button { padding: .7rem 1rem; border: 0; border-radius: 6px; background: #0f172a; color: white; cursor: pointer; }`,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class PendingComponent {
  private readonly clerk = inject(ClerkService);

  async signOut(): Promise<void> {
    await this.clerk.signOut();
  }
}
