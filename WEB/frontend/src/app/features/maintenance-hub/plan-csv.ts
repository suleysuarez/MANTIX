import { csvCell } from '../../core/csv';
import { MaintenanceSchedule } from '../../core/schedules.service';

export { csvCell };

/** Exportación CSV de planes preventivos. Funciones puras. */

const HEADERS = ['Plan', 'Equipo', 'Técnico', 'Intervalo (días)', 'Horas estimadas', 'Próximo servicio', 'Estado'];

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
