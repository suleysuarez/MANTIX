import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { ClerkService } from './clerk.service';

export const authGuard: CanActivateFn = async () => {
  const clerk = inject(ClerkService);
  const router = inject(Router);
  await clerk.initialize();
  return clerk.isSignedIn ? true : router.createUrlTree(['/auth/login']);
};
