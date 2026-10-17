import { HealthStatus } from '../../core/settings.service';

/** Textos y estados de la pantalla Configuración (lógica pura). */

export type ShownStatus = HealthStatus | 'never';

/** Estado con texto y símbolo, nunca solo color. Colores con contraste AA sobre fondo claro. */
export const STATUS: Record<ShownStatus, { label: string; symbol: string; tone: string; dot: string }> = {
  ok: { label: 'Operativo', symbol: '✓', tone: 'bg-[#D1FAE5] text-[#065F46]', dot: 'bg-[#10B981]' },
  warning: { label: 'Atención', symbol: '!', tone: 'bg-[#FEF3C7] text-[#92400E]', dot: 'bg-[#D97706]' },
  error: { label: 'Con fallo', symbol: '✕', tone: 'bg-[#FEE2E2] text-[#991B1B]', dot: 'bg-[#DC2626]' },
  disabled: { label: 'Desactivado', symbol: '–', tone: 'bg-[#E2E8F0] text-[#334155]', dot: 'bg-[#64748B]' },
  never: { label: 'Sin ejecutar', symbol: '–', tone: 'bg-[#E2E8F0] text-[#334155]', dot: 'bg-[#64748B]' },
};

/** La integración sana se lee «Conectada»; el resto usa el estado general. */
export function integrationLabel(status: HealthStatus): string {
  return status === 'ok' ? 'Conectada' : STATUS[status].label;
}

const JOB_NAMES: Record<string, string> = {
  'schedule-reminders': 'Recordatorios de mantenimiento preventivo',
};

/** El servidor nombra las tareas en inglés; aquí se muestran en español. */
export function jobName(job: { id: string; name: string }): string {
  return JOB_NAMES[job.id] ?? job.name;
}

export function frequencyText(minutes: number | null): string {
  if (!minutes || minutes < 1) {
    return '—';
  }
  if (minutes % 1440 === 0) {
    return minutes === 1440 ? 'Diaria' : `Cada ${minutes / 1440} días`;
  }
  if (minutes % 60 === 0) {
    return minutes === 60 ? 'Cada hora' : `Cada ${minutes / 60} h`;
  }
  return `Cada ${minutes} min`;
}

/** Estado de una tarea: detenida si el programador no corre; si no, el resultado de su última ejecución. */
export function jobStatus(job: { running: boolean; last_status: 'ok' | 'error' | 'never' }): ShownStatus {
  return job.running ? job.last_status : 'disabled';
}

export function jobStatusLabel(status: ShownStatus): string {
  return status === 'ok' ? 'Operativa' : STATUS[status].label;
}

const ACTIONS: Record<string, string> = {
  'auth.login': 'Inicio de sesión',
  'user.created': 'Creación de usuario',
  'user.updated': 'Edición de usuario',
  'user.activated': 'Activación de usuario',
  'user.deactivated': 'Desactivación de usuario',
  'user.password_reset': 'Restablecimiento de contraseña',
  'profile.updated': 'Edición de perfil',
  'profile.password_changed': 'Cambio de contraseña',
  'profile.avatar_updated': 'Cambio de foto de perfil',
  'roles.replaced': 'Cambio de roles',
  'roles.assigned': 'Asignación de rol',
  'roles.revoked': 'Retiro de rol',
  'category.created': 'Creación de categoría',
  'category.updated': 'Edición de categoría',
  'category.deleted': 'Eliminación de categoría',
  'priority.updated': 'Edición de prioridad',
  'organization.updated': 'Cambio de organización',
  'report.exported': 'Exportación de reporte',
  'equipment.created': 'Creación de equipo',
  'equipment.updated': 'Edición de equipo',
};

/** Acción de auditoría en español; lo desconocido se muestra tal cual, sin inventar. */
export function actionLabel(action: string): string {
  return ACTIONS[action] ?? action;
}

/** Tono del recuadro de «Salud»: avisa solo cuando hay algo que atender. */
export function attentionTone(count: number): string {
  return count > 0 ? 'bg-[#FEF3C7]' : 'bg-[#EEF4FA]';
}
