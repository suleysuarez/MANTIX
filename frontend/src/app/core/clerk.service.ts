import { Injectable, inject } from '@angular/core';
import { Router } from '@angular/router';
import { BehaviorSubject } from 'rxjs';
import { ClerkInstance, ClerkMountOptions, ClerkState } from './clerk.types';

@Injectable({ providedIn: 'root' })
export class ClerkService {
  private readonly stateSubject = new BehaviorSubject<ClerkState>({
    isSignedIn: false,
    user: null,
    session: null,
  });
  private readonly router = inject(Router);
  private clerk: ClerkInstance | null = null;
  private initialization: Promise<void> | null = null;
  private unsubscribe: (() => void) | null = null;

  readonly state$ = this.stateSubject.asObservable();

  async initialize(): Promise<void> {
    if (!this.initialization) {
      this.initialization = this.loadClerk();
    }
    return this.initialization;
  }

  get isSignedIn(): boolean {
    return this.stateSubject.value.isSignedIn;
  }

  async getToken(): Promise<string | null> {
    await this.initialize();
    return this.clerk?.session?.getToken() ?? null;
  }

  async signOut(): Promise<void> {
    await this.initialize();
    await this.clerk?.signOut();
  }

  async mountSignIn(node: HTMLElement, options?: ClerkMountOptions): Promise<void> {
    await this.initialize();
    this.clerk?.mountSignIn(node, options);
  }

  async unmountSignIn(node: HTMLElement): Promise<void> {
    await this.initialize();
    this.clerk?.unmountSignIn(node);
  }

  async mountSignUp(node: HTMLElement, options?: ClerkMountOptions): Promise<void> {
    await this.initialize();
    this.clerk?.mountSignUp(node, options);
  }

  async unmountSignUp(node: HTMLElement): Promise<void> {
    await this.initialize();
    this.clerk?.unmountSignUp(node);
  }

  async mountUserButton(node: HTMLElement): Promise<void> {
    await this.initialize();
    this.clerk?.mountUserButton(node);
  }

  async unmountUserButton(node: HTMLElement): Promise<void> {
    await this.initialize();
    this.clerk?.unmountUserButton(node);
  }

  private async loadClerk(): Promise<void> {
    const clerk = await this.waitForGlobalClerk();
    // Clerk navega con el Router de Angular (sin recargar la página) y conoce
    // las rutas de la app: tras iniciar sesión va al dashboard y tras cerrarla
    // a /auth/login.
    await clerk.load({
      ui: { ClerkUI: window.__internal_ClerkUICtor },
      routerPush: (to) => this.navigate(to, false),
      routerReplace: (to) => this.navigate(to, true),
      signInUrl: '/auth/login',
      signUpUrl: '/auth/sign-up',
      afterSignOutUrl: '/auth/login',
      signInFallbackRedirectUrl: '/dashboard',
      signUpFallbackRedirectUrl: '/dashboard',
    });
    this.clerk = clerk;
    this.publishState(clerk);
    this.unsubscribe = clerk.addListener((state) => this.publishState(state));
  }

  /**
   * Los pasos internos de SignIn/SignUp (verificación, callback de Google…)
   * viajan en el hash de la URL y el router interno de Clerk los lee con el
   * evento `hashchange`. `router.navigateByUrl` usa pushState, que no lo
   * dispara, así que los cambios solo de hash se hacen nativamente.
   */
  private navigate(to: string, replace: boolean): Promise<unknown> | void {
    const url = new URL(to, window.location.origin);
    if (url.pathname === window.location.pathname && url.hash) {
      if (replace) {
        window.location.replace(url.href);
      } else {
        window.location.hash = url.hash;
      }
      return;
    }
    return this.router.navigateByUrl(to, { replaceUrl: replace });
  }

  private publishState(state: ClerkState): void {
    this.stateSubject.next({
      isSignedIn: state.isSignedIn,
      user: state.user,
      session: state.session,
    });
  }

  private waitForGlobalClerk(): Promise<ClerkInstance> {
    return new Promise((resolve, reject) => {
      const startedAt = Date.now();
      const findClerk = () => {
        if (window.Clerk) {
          resolve(window.Clerk);
          return;
        }
        if (Date.now() - startedAt > 10000) {
          reject(new Error('ClerkJS did not load within 10 seconds'));
          return;
        }
        window.setTimeout(findClerk, 50);
      };
      findClerk();
    });
  }
}
