import { HistoryEntry, HistoryKind } from '../../core/profile.service';

/** Lógica pura de la pantalla Perfil: reglas de los formularios (las del backend) y textos del historial. */

export const PROFILE_LIMITS = { nameMin: 2, nameMax: 120, phoneMax: 25, passwordMin: 10, passwordMax: 128 } as const;
export const AVATAR_LIMITS = { maxBytes: 2 * 1024 * 1024, minSide: 64, types: ['image/png', 'image/jpeg'] } as const;

const PHONE = /^\+?[0-9][0-9 ()-]{5,24}$/;
const collapse = (value: string): string => value.trim().replace(/\s+/g, ' ');

export interface ProfileFormErrors {
  full_name?: string;
  phone?: string;
}

export function validateProfile(values: { full_name: string; phone: string }): ProfileFormErrors {
  const errors: ProfileFormErrors = {};
  const name = collapse(values.full_name);
  if (!name) {
    errors.full_name = 'El nombre es obligatorio.';
  } else if (name.length < PROFILE_LIMITS.nameMin) {
    errors.full_name = `Escribe al menos ${PROFILE_LIMITS.nameMin} caracteres.`;
  } else if (name.length > PROFILE_LIMITS.nameMax) {
    errors.full_name = `Máximo ${PROFILE_LIMITS.nameMax} caracteres.`;
  }
  const phone = collapse(values.phone);
  if (phone && !PHONE.test(phone)) {
    errors.phone = 'El teléfono solo admite números, espacios, +, ( ) y -.';
  }
  return errors;
}

/** Revisión previa de la foto (tipo y peso); las dimensiones se revisan al leerla. Vacío = válida. */
export function avatarFileError(file: Pick<File, 'type' | 'size'>): string {
  if (!(AVATAR_LIMITS.types as readonly string[]).includes(file.type)) {
    return 'La foto debe ser un PNG o un JPG.';
  }
  if (file.size > AVATAR_LIMITS.maxBytes) {
    return 'La foto pesa más de 2 MB: elige una más liviana.';
  }
  if (file.size === 0) {
    return 'El archivo está vacío.';
  }
  return '';
}

export function avatarSizeError(width: number, height: number): string {
  return Math.min(width, height) < AVATAR_LIMITS.minSide
    ? `La foto es muy pequeña: mínimo ${AVATAR_LIMITS.minSide}×${AVATAR_LIMITS.minSide} píxeles.`
    : '';
}

/** Lee las dimensiones de la imagen en el navegador (antes de subirla). */
export function imageSize(file: Blob): Promise<{ width: number; height: number }> {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const image = new Image();
    image.onload = () => {
      URL.revokeObjectURL(url);
      resolve({ width: image.naturalWidth, height: image.naturalHeight });
    };
    image.onerror = () => {
      URL.revokeObjectURL(url);
      reject(new Error('no es una imagen'));
    };
    image.src = url;
  });
}

/** Contraseña nueva (misma política del backend); devuelve el primer problema o `''`. */
export function newPasswordError(current: string, next: string, confirmation: string): string {
  if (!next) {
    return 'Escribe la nueva contraseña.';
  }
  if (next.length < PROFILE_LIMITS.passwordMin) {
    return `Debe tener al menos ${PROFILE_LIMITS.passwordMin} caracteres.`;
  }
  if (next.length > PROFILE_LIMITS.passwordMax) {
    return `Máximo ${PROFILE_LIMITS.passwordMax} caracteres.`;
  }
  if (/\s/.test(next)) {
    return 'No puede contener espacios.';
  }
  if (!/[a-z]/.test(next) || !/[A-Z]/.test(next) || !/[0-9]/.test(next)) {
    return 'Debe combinar mayúsculas, minúsculas y números.';
  }
  if (next === current) {
    return 'Debe ser distinta de la actual.';
  }
  if (next !== confirmation) {
    return 'Las contraseñas no coinciden.';
  }
  return '';
}

export const KIND_OPTIONS: { value: HistoryKind | ''; label: string }[] = [
  { value: '', label: 'Todo' },
  { value: 'session', label: 'Inicios de sesión' },
  { value: 'profile', label: 'Mis datos' },
  { value: 'security', label: 'Seguridad' },
  { value: 'activity', label: 'Otra actividad' },
];

const ACTIONS: Record<string, { label: string; icon: string }> = {
  'auth.login': { label: 'Iniciaste sesión', icon: 'login' },
  'profile.updated': { label: 'Actualizaste tus datos', icon: 'edit' },
  'profile.avatar_updated': { label: 'Cambiaste tu foto de perfil', icon: 'add_a_photo' },
  'profile.avatar_removed': { label: 'Eliminaste tu foto de perfil', icon: 'no_photography' },
  'profile.password_changed': { label: 'Cambiaste tu contraseña', icon: 'password' },
  'user.password_reset': { label: 'Tu contraseña fue restablecida', icon: 'key' },
  'user.created': { label: 'Tu cuenta fue registrada', icon: 'person_add' },
  'user.updated': { label: 'Tus datos fueron actualizados', icon: 'edit' },
  'user.activated': { label: 'Tu cuenta fue activada', icon: 'person_check' },
  'user.deactivated': { label: 'Tu cuenta fue desactivada', icon: 'person_off' },
  'roles.replaced': { label: 'Tus roles fueron actualizados', icon: 'admin_panel_settings' },
  'roles.assigned': { label: 'Se te asignó un rol', icon: 'admin_panel_settings' },
  'roles.revoked': { label: 'Se te quitó un rol', icon: 'admin_panel_settings' },
};

export const KIND_STYLES: Record<HistoryKind, string> = {
  session: 'bg-[#DBEAFE] text-[#1E40AF]',
  profile: 'bg-[#D1FAE5] text-[#065F46]',
  security: 'bg-[#FEF3C7] text-[#92400E]',
  activity: 'bg-[#E2E8F0] text-[#334155]',
};

export function actionInfo(entry: Pick<HistoryEntry, 'action'>): { label: string; icon: string } {
  return ACTIONS[entry.action] ?? { label: 'Actividad registrada', icon: 'history' };
}

/** «Por Ana Pérez» cuando lo hizo otra persona; vacío si fuiste tú. */
export function byText(entry: Pick<HistoryEntry, 'actor_name'>): string {
  return entry.actor_name ? `Por ${entry.actor_name}` : '';
}
