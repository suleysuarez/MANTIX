/** Formato y semántica de los KPI del dashboard. Funciones puras, sin Angular. */

import { AlertReason } from '../../core/dashboard-kpis.service';

export type Tone = 'good' | 'bad' | 'neutral';

const decimal = (value: number, digits = 1): string => value.toFixed(digits).replace('.', ',').replace(/,0$/, '');

/** «45 min», «12,5 h» o «3,2 d»: la unidad que mejor se lee según la magnitud. */
export function formatHours(hours: number | null): string {
  if (hours === null) {
    return '—';
  }
  if (hours < 1) {
    return `${Math.max(Math.round(hours * 60), 1)} min`;
  }
  return hours < 48 ? `${decimal(hours)} h` : `${decimal(hours / 24)} d`;
}

export function formatPct(value: number | null): string {
  return value === null ? '—' : `${decimal(value)}%`;
}

/** Variación con flecha: «▲ 12,5%». Vacío cuando no hay base de comparación. */
export function formatChange(changePct: number | null): string {
  if (changePct === null) {
    return '';
  }
  if (changePct === 0) {
    return '= 0%';
  }
  return `${changePct > 0 ? '▲' : '▼'} ${decimal(Math.abs(changePct))}%`;
}

/** Color semántico: depende de si subir es bueno (SLA) o malo (MTTR). */
export function changeTone(changePct: number | null, betterWhen: 'higher' | 'lower'): Tone {
  if (changePct === null || changePct === 0) {
    return 'neutral';
  }
  const improved = betterWhen === 'higher' ? changePct > 0 : changePct < 0;
  return improved ? 'good' : 'bad';
}

/**
 * Puntos de una polilínea SVG. Los huecos (`null`) se omiten; con menos de dos valores
 * no hay tendencia que dibujar y devuelve `null`.
 */
export function sparkline(values: (number | null)[], width: number, height: number): string | null {
  const points = values
    .map((value, index) => ({ value, index }))
    .filter((p): p is { value: number; index: number } => p.value !== null);
  if (points.length < 2) {
    return null;
  }
  const min = Math.min(...points.map((p) => p.value));
  const max = Math.max(...points.map((p) => p.value));
  const span = max - min || 1;
  const last = Math.max(values.length - 1, 1);
  return points
    .map((p) => {
      const x = (p.index / last) * width;
      const y = height - 2 - ((p.value - min) / span) * (height - 4);
      return `${x.toFixed(1)},${y.toFixed(1)}`;
    })
    .join(' ');
}

const REASONS: Record<AlertReason, string> = {
  unassigned_critical: 'Crítico sin asignar',
  sla_breached: 'SLA vencido',
  sla_at_risk: 'SLA por vencer',
};

export function reasonLabel(reason: AlertReason): string {
  return REASONS[reason];
}

/** «5 h», «1 d 6 h»: cuánto lleva caído un equipo. */
export function formatDowntime(hours: number | null): string {
  if (hours === null) {
    return 'Sin registro de fecha';
  }
  if (hours < 24) {
    return `${Math.max(Math.round(hours), 1)} h`;
  }
  const days = Math.floor(hours / 24);
  const rest = Math.round(hours - days * 24);
  return rest ? `${days} d ${rest} h` : `${days} d`;
}
