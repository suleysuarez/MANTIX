import { inject } from '@angular/core';
import { CanActivateFn, Router, UrlTree } from '@angular/router';

import { ClerkService } from './clerk.service';
import { LocalProfile, LocalProfileService } from './local-profile.service';

const UNAVAILABLE_ROUTE = ['/auth/unavailable'];
export const FORBIDDEN_ROUTE = ['/acceso-denegado'];

/** Perfil local, o `null` si la API no responde (así el guard redirige en vez de cancelar la navegación). */
async function tryProfile(profileService: LocalProfileService): Promise<LocalProfile | null> {
  try {
    return await profileService.getProfile();
  } catch {
    return null;
  }
}

export const authGuard: CanActivateFn = async () => {
  const clerk = inject(ClerkService);
  const router = inject(Router);
  await clerk.initialize();
  return clerk.isSignedIn ? true : router.createUrlTree(['/auth/login']);
};

/** Login/sign-up: solo para invitados; con sesión activa Clerk no monta SignIn. */
export const guestGuard: CanActivateFn = async () => {
  const clerk = inject(ClerkService);
  const router = inject(Router);
  await clerk.initialize();
  return clerk.isSignedIn ? router.createUrlTree(['/dashboard']) : true;
};

export const authorizedGuard: CanActivateFn = async () => {
  const clerk = inject(ClerkService);
  const profileService = inject(LocalProfileService);
  const router = inject(Router);
  await clerk.initialize();
  if (!clerk.isSignedIn) {
    return router.createUrlTree(['/auth/login']);
  }
  const profile = await tryProfile(profileService);
  if (!profile) {
    return router.createUrlTree(UNAVAILABLE_ROUTE);
  }
  return profile.roles.length > 0 ? true : router.createUrlTree(['/auth/pending']);
};

export const permissionGuard = (permission: string): CanActivateFn => async () => {
  const clerk = inject(ClerkService);
  const profileService = inject(LocalProfileService);
  const router = inject(Router);
  await clerk.initialize();
  if (!clerk.isSignedIn) {
    return router.createUrlTree(['/auth/login']);
  }
  const profile = await tryProfile(profileService);
  if (!profile) {
    return router.createUrlTree(UNAVAILABLE_ROUTE);
  }
  if (profile.permissions.some((item) => item.code === permission)) {
    return true;
  }
  // Sin ningún rol la cuenta sigue pendiente de aprobación; con rol pero sin permiso es un 403 visible.
  return router.createUrlTree((profile.roles ?? []).length > 0 ? FORBIDDEN_ROUTE : ['/auth/pending']);
};

/** Como `permissionGuard`, pero exige además alguno de los roles indicados. */
export const roleGuard =
  (permission: string, ...roles: string[]): CanActivateFn =>
  async (route, state) => {
    // `inject()` solo vale antes del primer `await`: después lanza NG0203 y la navegación se cancelaba en silencio.
    const profileService = inject(LocalProfileService);
    const router = inject(Router);
    const allowed = await (permissionGuard(permission)(route, state) as unknown as Promise<boolean | UrlTree>);
    if (allowed !== true) {
      return allowed;
    }
    const profile = await tryProfile(profileService);
    return profile?.roles.some((role) => roles.includes(role.code)) ? true : router.createUrlTree(FORBIDDEN_ROUTE);
  };
