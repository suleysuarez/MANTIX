export interface ClerkSession {
  getToken(): Promise<string | null>;
}

export interface ClerkUser {
  id: string;
  primaryEmailAddress?: { emailAddress: string } | null;
  fullName?: string | null;
  firstName?: string | null;
  lastName?: string | null;
}

export interface ClerkState {
  isSignedIn: boolean;
  user: ClerkUser | null;
  session: ClerkSession | null;
}

export type ClerkElementStyle = Record<string, string | number | ClerkElementStyle>;

export interface ClerkAppearance {
  variables?: Record<string, string>;
  elements?: Record<string, string | ClerkElementStyle>;
}

export interface ClerkMountOptions {
  appearance?: ClerkAppearance;
  signInUrl?: string;
  signUpUrl?: string;
}

export interface ClerkInstance extends ClerkState {
  load(options?: { ui?: { ClerkUI?: unknown } }): Promise<void>;
  addListener(listener: (state: ClerkState) => void): () => void;
  signOut(): Promise<void>;
  mountSignIn(node: HTMLElement, options?: ClerkMountOptions): void;
  unmountSignIn(node: HTMLElement): void;
  mountSignUp(node: HTMLElement, options?: ClerkMountOptions): void;
  unmountSignUp(node: HTMLElement): void;
  mountUserButton(node: HTMLElement): void;
  unmountUserButton(node: HTMLElement): void;
}

declare global {
  interface Window {
    Clerk?: ClerkInstance;
    __internal_ClerkUICtor?: unknown;
  }
}

export {};
