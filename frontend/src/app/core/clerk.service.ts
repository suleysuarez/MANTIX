import { Injectable } from '@angular/core';
import { BehaviorSubject } from 'rxjs';
import { ClerkInstance, ClerkMountOptions, ClerkState } from './clerk.types';

@Injectable({ providedIn: 'root' })
export class ClerkService {
  private readonly stateSubject = new BehaviorSubject<ClerkState>({
    isSignedIn: false,
    user: null,
    session: null,
  });
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
    await clerk.load({ ui: { ClerkUI: window.__internal_ClerkUICtor } });
    this.clerk = clerk;
    this.publishState(clerk);
    this.unsubscribe = clerk.addListener((state) => this.publishState(state));
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
