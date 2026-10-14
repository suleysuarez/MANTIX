import { HttpErrorResponse } from '@angular/common/http';

/**
 * Errores del backend en español, sin exponer detalles internos. El cuerpo de todo error
 * es `{ detail, code, errors?: [{ field, message, type }] }`; aquí solo se usa `code`,
 * `type` y `field`: el texto en inglés del servidor nunca llega al usuario.
 */
interface ApiErrorBody {
  detail?: string;
  code?: string;
  errors?: { field: string; message: string; type: string }[] | null;
}

const BY_CODE: Record<string, string> = {
  bad_request: 'La solicitud no es válida. Revisa los datos e inténtalo de nuevo.',
  forbidden: 'No tienes permiso para realizar esta acción.',
  not_found: 'El registro ya no existe. Actualiza la pantalla.',
  conflict: 'La acción no se puede realizar en el estado actual del registro.',
  validation_error: 'Revisa los campos marcados.',
  payload_too_large: 'El archivo supera el tamaño máximo permitido.',
  unsupported_media_type: 'El tipo de archivo no está permitido.',
  rate_limited: 'Demasiadas solicitudes. Espera un momento e inténtalo de nuevo.',
};

const BY_STATUS: Record<number, string> = {
  0: 'No se pudo conectar con el servidor. Revisa tu conexión e inténtalo de nuevo.',
  401: 'Tu sesión expiró. Inicia sesión de nuevo.',
  403: BY_CODE['forbidden'],
  404: BY_CODE['not_found'],
  409: BY_CODE['conflict'],
  413: BY_CODE['payload_too_large'],
  415: BY_CODE['unsupported_media_type'],
  422: BY_CODE['validation_error'],
  429: BY_CODE['rate_limited'],
};

/** Reglas de negocio conocidas (409): el servidor devuelve el texto en inglés. */
const BUSINESS_RULES: [RegExp, string][] = [
  [/inactive technician/i, 'No se puede asignar a un técnico inactivo.'],
  [/have not started/i, 'Solo se pueden rechazar solicitudes que aún no se han iniciado.'],
  [/cannot transition|not allowed/i, 'Ese cambio de estado no está permitido desde el estado actual.'],
];

function body(error: HttpErrorResponse): ApiErrorBody {
  return typeof error.error === 'object' && error.error !== null ? (error.error as ApiErrorBody) : {};
}

/** Mensaje legible para un fallo HTTP; `fallback` para lo que no es de la API. */
export function apiErrorMessage(error: unknown, fallback: string): string {
  if (!(error instanceof HttpErrorResponse)) {
    return fallback;
  }
  if (error.status >= 500) {
    return 'El servidor tuvo un problema. Inténtalo de nuevo más tarde.';
  }
  const { detail, code } = body(error);
  if (error.status === 409 && detail) {
    const rule = BUSINESS_RULES.find(([pattern]) => pattern.test(detail));
    if (rule) {
      return rule[1];
    }
  }
  return BY_STATUS[error.status] ?? (code && BY_CODE[code]) ?? fallback;
}

const BY_TYPE: Record<string, (message: string) => string> = {
  missing: () => 'Este campo es obligatorio.',
  string_too_short: (message) => {
    const min = /at least (\d+)/.exec(message)?.[1];
    return min ? `Debe tener al menos ${min} caracteres.` : 'Es demasiado corto.';
  },
  string_too_long: (message) => {
    const max = /at most (\d+)/.exec(message)?.[1];
    return max ? `Debe tener como máximo ${max} caracteres.` : 'Es demasiado largo.';
  },
  string_pattern_mismatch: () => 'El formato no es válido.',
  value_error: (message) => (/blank/i.test(message) ? 'No puede estar vacío.' : 'El valor no es válido.'),
  greater_than_equal: () => 'El valor es demasiado bajo.',
  less_than_equal: () => 'El valor es demasiado alto.',
  int_parsing: () => 'Debe ser un número entero.',
  datetime_parsing: () => 'La fecha no es válida.',
  date_parsing: () => 'La fecha no es válida.',
};

/** Errores por campo de una respuesta 422, ya en español: `{ reason: 'Debe tener…' }`. */
export function apiFieldErrors(error: unknown): Record<string, string> {
  if (!(error instanceof HttpErrorResponse) || error.status !== 422) {
    return {};
  }
  const result: Record<string, string> = {};
  for (const item of body(error).errors ?? []) {
    result[item.field] ??= (BY_TYPE[item.type] ?? (() => 'El valor no es válido.'))(item.message);
  }
  return result;
}
