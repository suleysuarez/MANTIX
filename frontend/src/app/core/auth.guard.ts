import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';

import { ClerkService } from './clerk.service';
import { LocalProfileService } from './local-profile.service';

export const authGuard: CanActivateFn = async () => {
  const clerk = inject(ClerkService);
  const router = inject(Router);
  await clerk.initialize();
  return clerk.isSignedIn ? true : router.createUrlTree(['/auth/login']);
};

export const authorizedGuard: CanActivateFn = async () => {
  const clerk = inject(ClerkService);
  const profileService = inject(LocalProfileService);
  const router = inject(Router);
  await clerk.initialize();
  if (!clerk.isSignedIn) {
    return router.createUrlTree(['/auth/login']);
  }
  const profile = await profileService.getProfile();
  return profile.roles.length > 0
    ? true
    : router.createUrlTree(['/auth/pending']);
};

export const permissionGuard = (permission: string): CanActivateFn => async () => {
  const clerk = inject(ClerkService);
  const profileService = inject(LocalProfileService);
  const router = inject(Router);
  await clerk.initialize();
  if (!clerk.isSignedIn) {
    return router.createUrlTree(['/auth/login']);
  }
  const profile = await profileService.getProfile();
  return profile.permissions.some((item) => item.code === permission)
    ? true
    : router.createUrlTree(['/auth/pending']);
};
