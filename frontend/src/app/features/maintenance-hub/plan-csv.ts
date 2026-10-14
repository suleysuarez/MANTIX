import { MaintenanceSchedule } from '../../core/schedules.service';

/** Exportación CSV de planes preventivos. Funciones puras. */

const HEADERS = ['Plan', 'Equipo', 'Técnico', 'Intervalo (días)', 'Horas estimadas', 'Próximo servicio', 'Estado'];

/**
 * Escapa una celda. Un texto que empieza por `=`, `+`, `-` o `@` lo interpretaría una hoja de
 * cálculo como fórmula (inyección CSV): se antepone un apóstrofo para que se lea como texto.
 */
export function csvCell(value: unknown): string {
  let text = String(value ?? '');
  if (/^[=+\-@\t\r]/.test(text)) {
    text = `'${text}`;
  }
  return /[",\n\r]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

export function planStatus(plan: MaintenanceSchedule, now: Date = new Date()): string {
  if (!plan.is_active) {
    return 'Inactivo';
  }
  return new Date(plan.next_due_at) < now ? 'Vencido' : 'Programado';
}

export function plansToCsv(plans: MaintenanceSchedule[], now: Date = new Date()): string {
  const rows = plans.map((plan) => [
    plan.title,
    `${plan.equipment.asset_tag} ${plan.equipment.brand} ${plan.equipment.model}`,
    plan.technician?.full_name ?? '',
    plan.interval_days,
    plan.estimated_hours ?? '',
    plan.next_due_at,
    planStatus(plan, now),
  ]);
  return [HEADERS, ...rows].map((row) => row.map(csvCell).join(',')).join('\r\n');
}
