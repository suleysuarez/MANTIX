import { ChangeDetectionStrategy, Component, ViewEncapsulation, inject } from '@angular/core';

import { ClerkService } from '../../core/clerk.service';
import { AUTH_SHELL_STYLES, AUTH_SHELL_TEMPLATE, AuthShellBase, CLERK_APPEARANCE } from './auth-shell';

@Component({
  standalone: true,
  template: AUTH_SHELL_TEMPLATE,
  styles: AUTH_SHELL_STYLES,
  encapsulation: ViewEncapsulation.None,
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class SignUpComponent extends AuthShellBase {
  private readonly clerk = inject(ClerkService);

  protected mount(host: HTMLElement): Promise<void> {
    return this.clerk.mountSignUp(host, { appearance: CLERK_APPEARANCE, signInUrl: '/auth/login' });
  }

  protected unmount(host: HTMLElement): Promise<void> {
    return this.clerk.unmountSignUp(host);
  }
}
