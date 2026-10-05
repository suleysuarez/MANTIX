export interface ClerkSessionActivity {
  browserName?: string;
  browserVersion?: string;
  deviceType?: string;
  ipAddress?: string;
  city?: string;
  country?: string;
  isMobile?: boolean;
}

export interface ClerkSession {
  id: string;
  lastActiveAt?: Date;
  latestActivity?: ClerkSessionActivity;
  getToken(): Promise<string | null>;
  revoke?(): Promise<unknown>;
}

export interface ClerkUser {
  id: string;
  primaryEmailAddress?: { emailAddress: string } | null;
  fullName?: string | null;
  firstName?: string | null;
  lastName?: string | null;
  getSessions?(): Promise<ClerkSession[]>;
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
  forceRedirectUrl?: string;
}

export interface ClerkLoadOptions {
  ui?: { ClerkUI?: unknown };
  routerPush?: (to: string) => Promise<unknown> | unknown;
  routerReplace?: (to: string) => Promise<unknown> | unknown;
  afterSignOutUrl?: string;
  signInUrl?: string;
  signUpUrl?: string;
  signInFallbackRedirectUrl?: string;
  signUpFallbackRedirectUrl?: string;
}

export interface ClerkInstance extends ClerkState {
  load(options?: ClerkLoadOptions): Promise<void>;
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
