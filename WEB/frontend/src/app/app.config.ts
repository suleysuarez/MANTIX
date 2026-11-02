import { ApplicationConfig, inject, provideAppInitializer } from '@angular/core';
import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { RedirectCommand, Router, provideRouter, withNavigationErrorHandler } from '@angular/router';

import { routes } from './app.routes';
import { authInterceptor } from './core/auth.interceptor';
import { watchAuthSession } from './core/auth-session';
import { ClerkService } from './core/clerk.service';
import { LocalProfileService } from './core/local-profile.service';
import { NotificationsStore } from './core/notifications.store';

export const appConfig: ApplicationConfig = {
  providers: [
    provideRouter(
      routes,
      // Una pantalla que no se puede descargar (versión vieja en caché) ya no deja el clic sin respuesta.
      withNavigationErrorHandler(() => new RedirectCommand(inject(Router).parseUrl('/error-carga'))),
    ),
    provideHttpClient(withInterceptors([authInterceptor])),
    provideAppInitializer(async () => {
      // `inject()` solo es válido en la parte síncrona del initializer: se
      // resuelve todo antes del primer `await`.
      const clerk = inject(ClerkService);
      const router = inject(Router);
      const profile = inject(LocalProfileService);
      const notifications = inject(NotificationsStore);
      await clerk.initialize();
      watchAuthSession({ clerk, router, profile, notifications });
    }),
  ],
};
