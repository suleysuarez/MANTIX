import { Injectable, inject } from '@angular/core';
import { BehaviorSubject, Observable } from 'rxjs';

import { apiErrorMessage, apiFieldErrors } from './api-errors';
import {
  CategoryAdmin, Organization, OrganizationPayload, PriorityAdmin, PriorityPayload, SettingsService, SystemHealth,
} from './settings.service';
import { ToastService } from './toast.service';

export interface SettingsState {
  health: SystemHealth | null;
  healthLoading: boolean;
  healthError: string;
  categories: CategoryAdmin[];
  categoriesLoading: boolean;
  categoriesError: string;
  priorities: PriorityAdmin[];
  prioritiesLoading: boolean;
  prioritiesError: string;
  organization: Organization | null;
  organizationLoading: boolean;
  organizationError: string;
  /** Alta o edición en curso: bloquea el doble envío. */
  saving: boolean;
  /** Errores de campo devueltos por el servidor (422/409), por nombre de campo. */
  fieldErrors: Record<string, string>;
}

const INITIAL: SettingsState = {
  health: null,
  healthLoading: true,
  healthError: '',
  categories: [],
  categoriesLoading: true,
  categoriesError: '',
  priorities: [],
  prioritiesLoading: true,
  prioritiesError: '',
  organization: null,
  organizationLoading: true,
  organizationError: '',
  saving: false,
  fieldErrors: {},
};

/** Observer pattern store de Configuración. */
@Injectable({ providedIn: 'root' })
export class SettingsStore {
  private readonly api = inject(SettingsService);
  private readonly toasts = inject(ToastService);
  private readonly subject = new BehaviorSubject<SettingsState>(INITIAL);

  readonly state$: Observable<SettingsState> = this.subject.asObservable();

  private get value(): SettingsState {
    return this.subject.value;
  }

  private patch(changes: Partial<SettingsState>): void {
    this.subject.next({ ...this.value, ...changes });
  }

  loadAll(): void {
    this.loadHealth();
    this.loadCategories();
    this.loadPriorities();
    this.loadOrganization();
  }

  loadHealth(): void {
    this.patch({ healthLoading: true, healthError: '' });
    this.api.health().subscribe({
      next: (health) => this.patch({ health, healthLoading: false }),
      error: (error) => this.patch({ healthLoading: false, healthError: apiErrorMessage(error, 'No se pudo leer la salud del sistema.') }),
    });
  }

  loadCategories(): void {
    this.patch({ categoriesLoading: true, categoriesError: '' });
    this.api.categories().subscribe({
      next: (categories) => this.patch({ categories, categoriesLoading: false }),
      error: (error) => this.patch({ categoriesLoading: false, categoriesError: apiErrorMessage(error, 'No se pudieron cargar las categorías.') }),
    });
  }

  loadPriorities(): void {
    this.patch({ prioritiesLoading: true, prioritiesError: '' });
    this.api.priorities().subscribe({
      next: (priorities) => this.patch({ priorities, prioritiesLoading: false }),
      error: (error) => this.patch({ prioritiesLoading: false, prioritiesError: apiErrorMessage(error, 'No se pudieron cargar las prioridades.') }),
    });
  }

  loadOrganization(): void {
    this.patch({ organizationLoading: true, organizationError: '' });
    this.api.organization().subscribe({
      next: (organization) => this.patch({ organization, organizationLoading: false }),
      error: (error) => this.patch({ organizationLoading: false, organizationError: apiErrorMessage(error, 'No se pudieron cargar los datos de la organización.') }),
    });
  }

  saveOrganization(body: OrganizationPayload): void {
    this.run(() => this.api.saveOrganization(body), 'Datos de la organización guardados.', 'No se pudieron guardar los datos.', () => this.loadOrganization());
  }

  clearFieldErrors(): void {
    this.patch({ fieldErrors: {} });
  }

  createCategory(body: { code: string; name: string }, done: () => void): void {
    this.run(() => this.api.createCategory(body), 'Categoría creada.', 'No se pudo crear la categoría.', () => {
      this.loadCategories();
      done();
    });
  }

  renameCategory(category: CategoryAdmin, name: string, done: () => void): void {
    this.run(() => this.api.updateCategory(category.id, { name }), 'Categoría actualizada.', 'No se pudo guardar la categoría.', () => {
      this.loadCategories();
      done();
    });
  }

  toggleCategory(category: CategoryAdmin): void {
    const message = category.is_active ? 'Categoría desactivada.' : 'Categoría reactivada.';
    this.run(() => this.api.updateCategory(category.id, { is_active: !category.is_active }), message, 'No se pudo cambiar el estado.', () => this.loadCategories());
  }

  deleteCategory(category: CategoryAdmin): void {
    this.run(() => this.api.deleteCategory(category.id), 'Categoría eliminada.', 'No se pudo eliminar la categoría.', () => this.loadCategories());
  }

  updatePriority(priority: PriorityAdmin, body: PriorityPayload, done: () => void): void {
    this.run(() => this.api.updatePriority(priority.id, body), 'Prioridad actualizada.', 'No se pudo guardar la prioridad.', () => {
      this.loadPriorities();
      done();
    });
  }

  /** Ejecuta una escritura: ignora un segundo envío mientras guarda y traduce los errores del servidor. */
  private run<T>(request: () => Observable<T>, success: string, failure: string, after: () => void): void {
    if (this.value.saving) {
      return;
    }
    this.patch({ saving: true, fieldErrors: {} });
    request().subscribe({
      next: () => {
        this.patch({ saving: false });
        this.toasts.success(success);
        after();
      },
      error: (error) => {
        this.patch({ saving: false, fieldErrors: apiFieldErrors(error) });
        this.toasts.error(apiErrorMessage(error, failure));
      },
    });
  }
}
