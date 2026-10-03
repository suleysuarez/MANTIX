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
 * Red de seguridad inversa: si la sesión se abre mientras se muestra login/sign-up
 * (p. ej. al terminar la verificación del registro) y Clerk no llegó a redirigir,
 * lleva al dashboard; los guards decidirán después si corresponde /auth/pending.
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
  // La primera emisión es el estado inicial (sesión ya restaurada), no un inicio de sesión nuevo.
  let initialState = true;
  clerk.state$
    .pipe(
      map((state) => (state.isSignedIn ? (state.user?.id ?? null) : null)),
      distinctUntilChanged(),
      startWith(null as string | null),
      pairwise(),
    )
    .subscribe(([previous, current]) => {
      const isInitial = initialState;
      initialState = false;
      if (previous === current) {
        return;
      }
      profile.clear();
      notifications.clear();
      const path = router.url.split(/[?#]/)[0];
      if (!isInitial && previous === null && current !== null && PUBLIC_AUTH_ROUTES.includes(path)) {
        void router.navigateByUrl('/dashboard');
        return;
      }
      if (previous !== null && current === null && !PUBLIC_AUTH_ROUTES.includes(path)) {
        void router.navigateByUrl('/auth/login');
      }
    });
}
