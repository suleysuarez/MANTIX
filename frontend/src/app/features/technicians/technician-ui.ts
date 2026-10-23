import { Technician, TechnicianWorkload } from '../../core/technicians.service';

/** Estado operativo derivado: disponibilidad del perfil y tickets abiertos que tiene asignados. */
export type TechnicianStatus = 'free' | 'busy' | 'unavailable';
export type TechnicianOrder = 'availability' | 'load' | 'resolved' | 'name';

/** Cuenta de usuario activa o inactiva. */
export type ActiveFilter = '' | 'active' | 'inactive';
export type AvailabilityFilter = '' | 'available' | 'unavailable';
/** Tickets abiertos: ninguno, 1 a 2, o 3 o más. */
export type LoadFilter = '' | 'none' | 'low' | 'high';

export interface TechnicianFilters {
  search: string;
  /** Combinación disponibilidad + carga que ponen las tarjetas de resumen. */
  status: '' | TechnicianStatus;
  specialty: string;
  active: ActiveFilter;
  availability: AvailabilityFilter;
  load: LoadFilter;
  order: TechnicianOrder;
}

export const EMPTY_TECHNICIAN_FILTERS: TechnicianFilters = {
  search: '',
  status: '',
  specialty: '',
  active: '',
  availability: '',
  load: '',
  order: 'availability',
};

export const ACTIVE_OPTIONS: { value: Exclude<ActiveFilter, ''>; label: string }[] = [
  { value: 'active', label: 'Activo' },
  { value: 'inactive', label: 'Inactivo' },
];
export const AVAILABILITY_OPTIONS: { value: Exclude<AvailabilityFilter, ''>; label: string }[] = [
  { value: 'available', label: 'Disponible' },
  { value: 'unavailable', label: 'No disponible' },
];
export const LOAD_OPTIONS: { value: Exclude<LoadFilter, ''>; label: string }[] = [
  { value: 'none', label: 'Sin tickets' },
  { value: 'low', label: '1 a 2 tickets' },
  { value: 'high', label: '3 o más tickets' },
];

/** Una cuenta sin dato (listas antiguas) se considera activa. */
export const isActiveAccount = (technician: Technician): boolean => technician.is_active !== false;

export function hasTechnicianFilters(filters: TechnicianFilters): boolean {
  return !!(filters.search || filters.status || filters.specialty || filters.active || filters.availability || filters.load);
}

function loadBucket(open: number): Exclude<LoadFilter, ''> {
  if (open === 0) {
    return 'none';
  }
  return open <= 2 ? 'low' : 'high';
}

export interface StatusStyle {
  label: string;
  chip: string;
  dot: string;
}

export const STATUS_STYLES: Record<TechnicianStatus, StatusStyle> = {
  free: { label: 'Disponible', chip: 'bg-[#D1FAE5] text-[#065F46]', dot: 'bg-[#10B981]' },
  busy: { label: 'Con tickets activos', chip: 'bg-[#FEF3C7] text-[#92400E]', dot: 'bg-[#D4A017]' },
  unavailable: { label: 'No disponible', chip: 'bg-[#E2E8F0] text-[#475569]', dot: 'bg-[#94A3B8]' },
};

export const ORDER_OPTIONS: { value: TechnicianOrder; label: string }[] = [
  { value: 'availability', label: 'Disponibilidad' },
  { value: 'load', label: 'Menor carga de tickets' },
  { value: 'resolved', label: 'Más tickets resueltos' },
  { value: 'name', label: 'Nombre' },
];

export const PAGE_SIZE = 9;
export const MAX_SPECIALIZATION = 100;
/** `hourly_rate` es NUMERIC(10, 2) en la base de datos. */
export const MAX_RATE = 99_999_999.99;

export type Loads = Record<number, TechnicianWorkload | undefined>;

export function technicianStatus(technician: Technician, loads: Loads): TechnicianStatus {
  if (!technician.is_available) {
    return 'unavailable';
  }
  return (loads[technician.id]?.open_tickets ?? 0) > 0 ? 'busy' : 'free';
}

/** La especialización es un texto libre: «Hardware, Redes» se muestra como dos etiquetas. */
export function specialties(technician: Technician): string[] {
  return (technician.specialization ?? '')
    .split(/[,;]/)
    .map((part) => part.trim())
    .filter(Boolean);
}

/** Minúsculas y sin tildes, para que «sofia» encuentre a «Sofía». */
export function normalize(value: string): string {
  return value.normalize('NFD').replace(/\p{Diacritic}/gu, '').toLowerCase();
}

export function allSpecialties(technicians: readonly Technician[]): string[] {
  const seen = new Map<string, string>();
  for (const technician of technicians) {
    for (const item of specialties(technician)) {
      seen.set(normalize(item), seen.get(normalize(item)) ?? item);
    }
  }
  return [...seen.values()].sort((a, b) => a.localeCompare(b, 'es'));
}

const STATUS_RANK: Record<TechnicianStatus, number> = { free: 0, busy: 1, unavailable: 2 };

/** Filtra y ordena los técnicos de la pantalla (la lista es corta: se hace en el cliente). */
export function filterTechnicians(
  technicians: readonly Technician[],
  loads: Loads,
  filters: TechnicianFilters,
): Technician[] {
  const query = normalize(filters.search.trim());
  const specialty = normalize(filters.specialty);
  const open = (t: Technician) => loads[t.id]?.open_tickets ?? 0;
  const resolved = (t: Technician) => loads[t.id]?.resolved_in_window ?? 0;

  const matches = technicians.filter((technician) => {
    if (filters.status && technicianStatus(technician, loads) !== filters.status) {
      return false;
    }
    if (specialty && !specialties(technician).some((item) => normalize(item) === specialty)) {
      return false;
    }
    if (filters.active && isActiveAccount(technician) !== (filters.active === 'active')) {
      return false;
    }
    if (filters.availability && technician.is_available !== (filters.availability === 'available')) {
      return false;
    }
    if (filters.load && loadBucket(open(technician)) !== filters.load) {
      return false;
    }
    if (!query) {
      return true;
    }
    const haystack = normalize(
      [technician.full_name, technician.email, technician.employee_code, technician.specialization].join(' '),
    );
    return haystack.includes(query);
  });

  const byName = (a: Technician, b: Technician) => a.full_name.localeCompare(b.full_name, 'es');
  const comparators: Record<TechnicianOrder, (a: Technician, b: Technician) => number> = {
    availability: (a, b) =>
      STATUS_RANK[technicianStatus(a, loads)] - STATUS_RANK[technicianStatus(b, loads)] || byName(a, b),
    load: (a, b) => open(a) - open(b) || byName(a, b),
    resolved: (a, b) => resolved(b) - resolved(a) || byName(a, b),
    name: byName,
  };
  return [...matches].sort(comparators[filters.order]);
}

export interface TechnicianSummary {
  total: number;
  available: number;
  busy: number;
  unavailable: number;
  openTickets: number;
  resolved: number;
}

export function summarize(technicians: readonly Technician[], loads: Loads): TechnicianSummary {
  const summary: TechnicianSummary = {
    total: technicians.length, available: 0, busy: 0, unavailable: 0, openTickets: 0, resolved: 0,
  };
  for (const technician of technicians) {
    const status = technicianStatus(technician, loads);
    if (status === 'unavailable') {
      summary.unavailable++;
    } else {
      summary.available++;
      if (status === 'busy') {
        summary.busy++;
      }
    }
    summary.openTickets += loads[technician.id]?.open_tickets ?? 0;
    summary.resolved += loads[technician.id]?.resolved_in_window ?? 0;
  }
  return summary;
}

export interface TechnicianInput {
  /** Solo al crear: el usuario al que se le abre el perfil. */
  userId?: number | null;
  specialization: string;
  rate: string;
}

/** Primer problema de los datos del formulario, o `''` si son válidos. */
export function validateTechnicianInput(input: TechnicianInput, creating: boolean): string {
  if (creating && !input.userId) {
    return 'Selecciona el usuario al que pertenece el perfil de técnico.';
  }
  if (input.specialization.trim().length > MAX_SPECIALIZATION) {
    return `La especialización no puede superar los ${MAX_SPECIALIZATION} caracteres.`;
  }
  const rate = input.rate.trim();
  if (rate) {
    const value = Number(rate);
    if (!Number.isFinite(value) || value < 0) {
      return 'La tarifa por hora debe ser un número igual o mayor a cero.';
    }
    if (Math.round(value * 100) !== Number((value * 100).toFixed(4))) {
      return 'La tarifa por hora admite como máximo dos decimales.';
    }
    if (value > MAX_RATE) {
      return 'La tarifa por hora supera el máximo permitido.';
    }
  }
  return '';
}
