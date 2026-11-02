import { HttpErrorResponse, HttpHandlerFn, HttpInterceptorFn, HttpRequest } from '@angular/common/http';
import { inject } from '@angular/core';
import { Observable, catchError, from, switchMap, throwError } from 'rxjs';

import { apiErrorMessage } from './api-errors';
import { apiBaseUrl } from './api.config';
import { ClerkService } from './clerk.service';
import { ToastService } from './toast.service';

/** Marca la petición que ya se reintentó con un token nuevo: no se reintenta dos veces. */
const RETRIED = 'X-Auth-Retry';

function withToken(request: HttpRequest<unknown>, token: string | null): HttpRequest<unknown> {
  return token ? request.clone({ setHeaders: { Authorization: `Bearer ${token}` } }) : request;
}

/**
 * Token en cada llamada a la API y manejo central de los dos fallos de acceso:
 *
 * - 401: la sesión pudo caducar; se pide un token nuevo y se reintenta UNA vez. Si sigue sin valer,
 *   se cierra la sesión (Clerk lleva a la pantalla de ingreso).
 * - 403: hay sesión pero no permiso; se avisa con un mensaje claro (el del servidor ya está en español
 *   y sin detalles internos). Un aviso idéntico ya visible no se duplica, así que las pantallas que
 *   también avisan no repiten el mensaje.
 */
export const authInterceptor: HttpInterceptorFn = (request, next) => {
  if (!request.url.startsWith(apiBaseUrl())) {
    return next(request);
  }

  const clerk = inject(ClerkService);
  const toasts = inject(ToastService);

  const refreshAndRetry = (next: HttpHandlerFn, error: HttpErrorResponse): Observable<never> | ReturnType<HttpHandlerFn> =>
    from(clerk.refreshToken()).pipe(
      switchMap((token) => {
        if (!token) {
          void clerk.signOut();
          return throwError(() => error);
        }
        return next(withToken(request.clone({ setHeaders: { [RETRIED]: '1' } }), token)).pipe(
          catchError((retryError: unknown) => {
            if (retryError instanceof HttpErrorResponse && retryError.status === 401) {
              void clerk.signOut();
            }
            return throwError(() => retryError);
          }),
        );
      }),
    );

  return from(clerk.getToken()).pipe(
    switchMap((token) => next(withToken(request, token))),
    catchError((error: unknown) => {
      if (error instanceof HttpErrorResponse) {
        if (error.status === 401 && !request.headers.has(RETRIED)) {
          return refreshAndRetry(next, error);
        }
        if (error.status === 403) {
          toasts.error(apiErrorMessage(error, 'No tienes permiso para realizar esta acción.'));
        }
      }
      return throwError(() => error);
    }),
  );
};
