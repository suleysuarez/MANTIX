import { ManagedAccount } from '../../core/users.service';

/** Lógica pura de la pantalla de usuarios: reglas de los formularios (las mismas que el backend) y textos. */

export const USER_LIMITS = { nameMin: 2, nameMax: 120, phoneMax: 25, codeMax: 50, passwordMin: 10, passwordMax: 128 } as const;

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const PHONE = /^\+?[0-9][0-9 ()-]{5,24}$/;
const CODE = /^[A-Za-z0-9][A-Za-z0-9._-]{1,49}$/;

export interface UserFormValues {
  full_name: string;
  email: string;
  phone: string;
  employee_code: string;
  role_ids: number[];
}

export type UserFormErrors = Partial<Record<keyof UserFormValues, string>>;

const collapse = (value: string): string => value.trim().replace(/\s+/g, ' ');

/** Errores por campo en español; vacío si todo es válido. `emailLocked`: la cuenta ya inició sesión. */
export function validateUserForm(values: UserFormValues, requireRoles: boolean): UserFormErrors {
  const errors: UserFormErrors = {};
  const name = collapse(values.full_name);
  if (!name) {
    errors.full_name = 'El nombre es obligatorio.';
  } else if (name.length < USER_LIMITS.nameMin) {
    errors.full_name = `Escribe al menos ${USER_LIMITS.nameMin} caracteres.`;
  } else if (name.length > USER_LIMITS.nameMax) {
    errors.full_name = `Máximo ${USER_LIMITS.nameMax} caracteres.`;
  }
  const email = values.email.trim();
  if (!email) {
    errors.email = 'El correo es obligatorio.';
  } else if (!EMAIL.test(email)) {
    errors.email = 'Escribe un correo válido, como nombre@empresa.com.';
  }
  const phone = collapse(values.phone);
  if (phone && !PHONE.test(phone)) {
    errors.phone = 'El teléfono solo admite números, espacios, +, ( ) y -.';
  }
  const code = values.employee_code.trim();
  if (code && !CODE.test(code)) {
    errors.employee_code = 'El código solo admite letras, números, punto, guion y guion bajo (2 a 50).';
  }
  if (requireRoles && values.role_ids.length === 0) {
    errors.role_ids = 'Elige al menos un rol.';
  }
  return errors;
}

export function hasErrors(errors: object): boolean {
  return Object.values(errors).some(Boolean);
}

/** Política de contraseña (la misma del backend); devuelve el primer problema o `''`. */
export function passwordError(password: string, confirmation: string): string {
  if (!password) {
    return 'Escribe la nueva contraseña.';
  }
  if (password.length < USER_LIMITS.passwordMin) {
    return `Debe tener al menos ${USER_LIMITS.passwordMin} caracteres.`;
  }
  if (password.length > USER_LIMITS.passwordMax) {
    return `Máximo ${USER_LIMITS.passwordMax} caracteres.`;
  }
  if (/\s/.test(password)) {
    return 'No puede contener espacios.';
  }
  if (!/[a-z]/.test(password) || !/[A-Z]/.test(password) || !/[0-9]/.test(password)) {
    return 'Debe combinar mayúsculas, minúsculas y números.';
  }
  if (password !== confirmation) {
    return 'Las contraseñas no coinciden.';
  }
  return '';
}

export type AccessState = 'never' | 'active' | 'inactive';

export const ACCESS_LABEL: Record<AccessState, string> = {
  active: 'Activo',
  inactive: 'Inactivo',
  never: 'Pendiente de primer ingreso',
};

/** Estado de la cuenta para el chip: inactiva manda; si está activa y nunca entró, queda pendiente. */
export function accessState(user: Pick<ManagedAccount, 'is_active' | 'last_login_at'>): AccessState {
  if (!user.is_active) {
    return 'inactive';
  }
  return user.last_login_at ? 'active' : 'never';
}

/** Chips con contraste AA sobre fondo claro. */
export const ACCESS_STYLES: Record<AccessState, { chip: string; dot: string }> = {
  active: { chip: 'bg-[#D1FAE5] text-[#065F46]', dot: 'bg-[#10B981]' },
  inactive: { chip: 'bg-[#E2E8F0] text-[#334155]', dot: 'bg-[#64748B]' },
  never: { chip: 'bg-[#FEF3C7] text-[#92400E]', dot: 'bg-[#D97706]' },
};

export function lastAccessText(value: string | null, now: Date = new Date()): string {
  if (!value) {
    return 'Nunca';
  }
  const date = new Date(value);
  const minutes = Math.floor((now.getTime() - date.getTime()) / 60000);
  if (minutes < 1) {
    return 'Ahora mismo';
  }
  if (minutes < 60) {
    return `Hace ${minutes} min`;
  }
  const hours = Math.floor(minutes / 60);
  if (hours < 24) {
    return `Hace ${hours} h`;
  }
  const days = Math.floor(hours / 24);
  if (days < 30) {
    return `Hace ${days} ${days === 1 ? 'día' : 'días'}`;
  }
  return date.toLocaleDateString('es-CO', { day: '2-digit', month: 'short', year: 'numeric' });
}

export function roleNames(user: Pick<ManagedAccount, 'roles'>): string {
  return user.roles.map((role) => role.name).join(', ') || 'Sin rol';
}
