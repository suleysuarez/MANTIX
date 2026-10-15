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

describe('apiErrorMessage: export validation (422)', () => {
  const unprocessable = (detail: string, errors?: { field: string; message: string; type: string }[]) =>
    new HttpErrorResponse({ status: 422, error: { code: 'unprocessable', detail, errors } });

  it('explains each rule of an export in Spanish', () => {
    const cases: [string, string][] = [
      ['no records match the filters; nothing to export', 'No hay registros que coincidan con los filtros: no hay nada que exportar.'],
      ['the export has 12000 records and the limit is 10000; narrow the filters', 'Hay demasiados registros para exportar (máximo 10.000). Acota los filtros.'],
      ['unknown columns: nope', 'Alguna de las columnas elegidas no existe en este reporte.'],
      ["the report 'equipment' cannot be exported yet", 'Este reporte todavía no se puede exportar.'],
    ];
    for (const [detail, message] of cases) {
      expect(apiErrorMessage(unprocessable(detail), 'x')).toBe(message);
    }
  });

  it('reads the range rules out of the field errors', () => {
    const range = (message: string) => unprocessable('validation error', [{ field: 'filters', message, type: 'value_error' }]);
    expect(apiErrorMessage(range('Value error, date_to cannot be before date_from'), 'x')).toBe('La fecha final no puede ser anterior a la inicial.');
    expect(apiErrorMessage(range('Value error, the date range cannot exceed 366 days'), 'x')).toBe('El rango de fechas no puede superar 366 días.');
    expect(apiErrorMessage(range('Value error, date_from cannot be in the future'), 'x')).toBe('La fecha inicial no puede ser futura.');
  });

  it('keeps the generic message for any other 422 and never leaks the server text', () => {
    expect(apiErrorMessage(unprocessable('something internal'), 'x')).toBe('Revisa los campos marcados.');
  });
});
