import { HttpErrorResponse, HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { Router } from '@angular/router';
import { Observable, catchError, finalize, shareReplay, switchMap, throwError } from 'rxjs';
import { AuthService, TokenResponse } from './auth.service';

let refreshRequest: Observable<TokenResponse> | null = null;

export const authInterceptor: HttpInterceptorFn = (request, next) => {
  const auth = inject(AuthService);
  const router = inject(Router);
  const token = auth.accessToken;
  const isAuthRequest = request.url.includes('/auth/login') || request.url.includes('/auth/refresh');
  const authorizedRequest = token && !isAuthRequest
    ? request.clone({ setHeaders: { Authorization: `Bearer ${token}` } })
    : request;

  return next(authorizedRequest).pipe(
    catchError((error: HttpErrorResponse) => {
      if (error.status !== 401 || isAuthRequest || !auth.refreshToken) {
        return throwError(() => error);
      }
      if (!refreshRequest) {
        refreshRequest = auth.refresh().pipe(
          shareReplay(1),
          finalize(() => (refreshRequest = null)),
        );
      }
      return refreshRequest.pipe(
        switchMap(() => {
          const retry = request.clone({ setHeaders: { Authorization: `Bearer ${auth.accessToken}` } });
          return next(retry);
        }),
        catchError((refreshError) => {
          auth.clearSession();
          void router.navigate(['/auth/login']);
          return throwError(() => refreshError);
        }),
      );
    }),
  );
};
