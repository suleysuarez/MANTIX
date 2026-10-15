import { HttpErrorResponse } from '@angular/common/http';

import { apiErrorMessage, apiFieldErrors } from './api-errors';

const failure = (status: number, error: unknown = {}) => new HttpErrorResponse({ status, error });

describe('apiErrorMessage', () => {
  it('translates each status without leaking the server text', () => {
    expect(apiErrorMessage(failure(403, { detail: 'only ADMIN or SUPERVISOR can perform this action' }), 'x'))
      .toBe('No tienes permiso para realizar esta acción.');
    expect(apiErrorMessage(failure(404, { detail: 'maintenance request not found' }), 'x'))
      .toBe('El registro ya no existe. Actualiza la pantalla.');
    expect(apiErrorMessage(failure(0), 'x')).toContain('No se pudo conectar');
    expect(apiErrorMessage(failure(500, { detail: 'KeyError: secret' }), 'x'))
      .toBe('El servidor tuvo un problema. Inténtalo de nuevo más tarde.');
  });

  it('knows the business rules behind a 409 and falls back to a generic conflict', () => {
    expect(apiErrorMessage(failure(409, { detail: 'cannot assign a ticket to an inactive technician' }), 'x'))
      .toBe('No se puede asignar a un técnico inactivo.');
    expect(apiErrorMessage(failure(409, { detail: 'only requests that have not started can be rejected (current status: closed)' }), 'x'))
      .toBe('Solo se pueden rechazar solicitudes que aún no se han iniciado.');
    expect(apiErrorMessage(failure(409, { detail: 'something new' }), 'x'))
      .toBe('La acción no se puede realizar en el estado actual del registro.');
  });

  it('uses the screen fallback for anything that is not an HTTP error', () => {
    expect(apiErrorMessage(new Error('boom'), 'No se pudo guardar.')).toBe('No se pudo guardar.');
  });
});

describe('apiFieldErrors', () => {
  it('maps 422 field errors to Spanish messages', () => {
    const errors = apiFieldErrors(failure(422, {
      errors: [
        { field: 'reason', message: 'String should have at least 5 characters', type: 'string_too_short' },
        { field: 'title', message: 'Field required', type: 'missing' },
        { field: 'reason', message: 'second error for the same field', type: 'missing' },
      ],
    }));
    expect(errors).toEqual({ reason: 'Debe tener al menos 5 caracteres.', title: 'Este campo es obligatorio.' });
  });

  it('returns nothing for other statuses or malformed bodies', () => {
    expect(apiFieldErrors(failure(409, { errors: [{ field: 'a', message: 'm', type: 'missing' }] }))).toEqual({});
    expect(apiFieldErrors(failure(422, 'plain text'))).toEqual({});
    expect(apiFieldErrors(new Error('x'))).toEqual({});
  });
});
