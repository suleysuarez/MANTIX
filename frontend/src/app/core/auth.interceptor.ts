import { HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { from } from 'rxjs';
import { switchMap } from 'rxjs/operators';
import { ClerkService } from './clerk.service';

const apiUrl = 'http://localhost:8000';

export const authInterceptor: HttpInterceptorFn = (request, next) => {
  if (!request.url.startsWith(apiUrl)) {
    return next(request);
  }

  const clerk = inject(ClerkService);
  return from(clerk.getToken()).pipe(
    switchMap((token) => {
      const authorizedRequest = token
        ? request.clone({ setHeaders: { Authorization: `Bearer ${token}` } })
        : request;
      return next(authorizedRequest);
    }),
  );
};
