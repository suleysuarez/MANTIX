/**
 * URL base del backend FastAPI. Se lee en tiempo de ejecución de
 * `assets/config.json` (en Docker lo genera el contenedor a partir de la
 * variable `API_URL`), de modo que la misma imagen sirve para cualquier
 * entorno. Si el archivo no existe o es inválido se usa el valor por defecto.
 */
const DEFAULT_API_URL = 'http://localhost:8000';

let apiUrl = DEFAULT_API_URL;

export function apiBaseUrl(): string {
  return apiUrl;
}

export async function loadRuntimeConfig(url = '/assets/config.json'): Promise<void> {
  try {
    const response = await fetch(url, { cache: 'no-store' });
    if (!response.ok) {
      return;
    }
    const config = (await response.json()) as { apiUrl?: unknown };
    if (typeof config.apiUrl === 'string' && config.apiUrl.trim()) {
      apiUrl = config.apiUrl.trim().replace(/\/+$/, '');
    }
  } catch {
    // Sin configuración de tiempo de ejecución: se conserva el valor por defecto.
  }
}
