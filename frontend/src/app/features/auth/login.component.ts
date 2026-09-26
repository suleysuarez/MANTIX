import {
  AfterViewInit,
  ChangeDetectionStrategy,
  Component,
  ElementRef,
  OnDestroy,
  ViewChild,
  inject,
} from '@angular/core';

import { ClerkService } from '../../core/clerk.service';

@Component({
  standalone: true,
  template: `
    <main class="auth-page">
      <section class="auth-card">
        <h1>Technology Equipment Maintenance</h1>
        <p>Sign in to manage your maintenance workspace.</p>
        <div #signInHost aria-label="Clerk sign-in"></div>
      </section>
    </main>
  `,
  styles: [
    `.auth-page { min-height: 100vh; display: grid; place-items: center; background: #f1f5f9; }
     .auth-card { width: min(92vw, 480px); padding: 2rem; background: white; border-radius: 12px; box-shadow: 0 10px 30px #0f172a1a; }`,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class LoginComponent implements AfterViewInit, OnDestroy {
  @ViewChild('signInHost', { static: true }) private readonly signInHost!: ElementRef<HTMLElement>;
  private readonly clerk = inject(ClerkService);

  async ngAfterViewInit(): Promise<void> {
    await this.clerk.mountSignIn(this.signInHost.nativeElement);
  }

  async ngOnDestroy(): Promise<void> {
    await this.clerk.unmountSignIn(this.signInHost.nativeElement);
  }
}
