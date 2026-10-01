import { Router } from '@angular/router';
import { distinctUntilChanged, map, pairwise, startWith } from 'rxjs/operators';

import { ClerkService } from './clerk.service';
import { LocalProfileService } from './local-profile.service';
import { NotificationsStore } from './notifications.store';

const PUBLIC_AUTH_ROUTES = ['/auth/login', '/auth/sign-up'];

/**
 * Reacciona a la sesión de Clerk (fuente de verdad): al cambiar de usuario o
 * cerrar sesión descarta el perfil local cacheado (evita ver el rol del usuario
 * anterior) y, si la sesión termina fuera de las pantallas públicas, vuelve a
 * /auth/login aunque el cierre no haya venido de Clerk (otra pestaña, expiración).
 */
export interface AuthSessionDeps {
  clerk: ClerkService;
  router: Router;
  profile: LocalProfileService;
  notifications: NotificationsStore;
}

/**
 * No llama a `inject()`: las dependencias se resuelven en un contexto de
 * inyección válido (ver app.config.ts) y se pasan como argumentos.
 */
export function watchAuthSession({ clerk, router, profile, notifications }: AuthSessionDeps): void {
  clerk.state$
    .pipe(
      map((state) => (state.isSignedIn ? (state.user?.id ?? null) : null)),
      distinctUntilChanged(),
      startWith(null as string | null),
      pairwise(),
    )
    .subscribe(([previous, current]) => {
      if (previous === current) {
        return;
      }
      profile.clear();
      notifications.clear();
      const path = router.url.split(/[?#]/)[0];
      if (previous !== null && current === null && !PUBLIC_AUTH_ROUTES.includes(path)) {
        void router.navigateByUrl('/auth/login');
      }
    });
}
