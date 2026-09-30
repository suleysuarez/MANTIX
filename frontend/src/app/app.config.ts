import { ApplicationConfig, inject, provideAppInitializer } from '@angular/core';
import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { Router, provideRouter } from '@angular/router';

import { routes } from './app.routes';
import { authInterceptor } from './core/auth.interceptor';
import { watchAuthSession } from './core/auth-session';
import { ClerkService } from './core/clerk.service';
import { LocalProfileService } from './core/local-profile.service';

export const appConfig: ApplicationConfig = {
  providers: [
    provideRouter(routes),
    provideHttpClient(withInterceptors([authInterceptor])),
    provideAppInitializer(async () => {
      // `inject()` solo es válido en la parte síncrona del initializer: se
      // resuelve todo antes del primer `await`.
      const clerk = inject(ClerkService);
      const router = inject(Router);
      const profile = inject(LocalProfileService);
      await clerk.initialize();
      watchAuthSession({ clerk, router, profile });
    }),
  ],
};
