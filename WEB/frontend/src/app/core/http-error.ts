import { HttpErrorResponse } from '@angular/common/http';

/**
 * Mensaje para el usuario según el tipo de fallo HTTP. Los errores que no son
 * de red/autorización/servidor (p. ej. 400, 404, 409) usan el mensaje propio
 * de cada pantalla, que sabe qué operación falló.
 */
export function httpErrorMessage(error: unknown, fallback: string): string {
  if (!(error instanceof HttpErrorResponse)) {
    return fallback;
  }
  if (error.status === 0) {
    return 'The server cannot be reached. Check your connection and try again.';
  }
  if (error.status === 401) {
    return 'Your session has expired. Please sign in again.';
  }
  if (error.status === 403) {
    return 'You do not have permission to perform this action.';
  }
  if (error.status === 429) {
    return 'Too many requests. Wait a moment and try again.';
  }
  if (error.status >= 500) {
    return 'The server had a problem. Please try again later.';
  }
  return fallback;
}
