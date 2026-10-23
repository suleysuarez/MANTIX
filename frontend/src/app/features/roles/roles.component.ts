import { HttpErrorResponse } from '@angular/common/http';
import { ChangeDetectionStrategy, Component, DestroyRef, OnInit, computed, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { Observable, firstValueFrom, forkJoin } from 'rxjs';

import { apiErrorMessage } from '../../core/api-errors';
import { permissionLabel } from '../../core/permission-labels';
import { PermissionsService } from '../../core/permissions.service';
import { PermissionInfo, RoleAdmin, RoleUpdatePayload, RolesAdminService } from '../../core/roles-admin.service';
import { ToastService } from '../../core/toast.service';
import { ToastHostComponent } from '../../shared/toast-host.component';
import { RoleFormModalComponent, RoleFormResult } from './role-form-modal.component';
import { RolePreviewModalComponent } from './role-preview-modal.component';
import { CellState, Draft, MatrixGroup, buildMatrix, draftChanges, lockedReason, previewRole, resolveCell, serverRoleMessage, toggleDraft } from './roles-ui';

const FOCUS = 'focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep';
const ICON_BUTTON = `flex h-7 w-7 items-center justify-center rounded-lg bg-transparent !text-on-surface-variant transition-colors hover:bg-surface-container disabled:opacity-40 ${FOCUS}`;

type Modal =
  | { kind: 'create' }
  | { kind: 'edit'; role: RoleAdmin }
  | { kind: 'preview'; role: RoleAdmin }
  | { kind: 'delete'; role: RoleAdmin }
  | { kind: 'discard' }
  | null;

/**
 * Roles y permisos (solo quien puede asignar roles): una matriz recurso × acción × rol. Los permisos
 * que un rol hereda se ven bloqueados con el rol del que vienen; los propios se marcan y desmarcan, y
 * se guardan juntos. Aquí también se crean, renombran, reubican, desactivan y eliminan los roles
 * personalizados. El servidor vuelve a comprobar cada regla y deja cada cambio en la auditoría.
 */
@Component({
  selector: 'app-roles',
  standalone: true,
  imports: [ToastHostComponent, RoleFormModalComponent, RolePreviewModalComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="space-y-4">
      <header class="relative overflow-hidden rounded-2xl bg-gradient-to-r from-brand-sidebar to-primary-container px-6 py-5 md:px-8">
        <div class="flex flex-col gap-2.5 md:flex-row md:items-end md:justify-between">
          <div class="space-y-2">
            <span class="glass inline-flex w-fit items-center gap-2 rounded-full px-3 py-1 text-[11px] font-bold uppercase tracking-[0.08em] text-brand-accentDeep">
              <span class="h-2 w-2 rounded-full bg-brand-mustard"></span> Control de accesos
            </span>
            <h1 class="text-[24px] font-extrabold uppercase leading-tight tracking-tight text-white">Roles <span class="text-brand-accentLight">y permisos</span></h1>
            <p class="max-w-xl text-[13px] leading-snug text-brand-grey">Define qué puede hacer cada rol. Un rol recibe todo lo que concede el rol del que hereda, más lo que se le marque aquí.</p>
          </div>
          <button type="button" (click)="modal.set({ kind: 'create' })" class="glass-btn flex items-center gap-1.5 rounded-xl px-5 py-2.5 text-[13px] font-bold transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white">
            <span class="material-symbols-outlined text-[20px]" aria-hidden="true">add_moderator</span> Nuevo rol
          </button>
        </div>
      </header>

      @if (error()) {
        <p role="alert" class="flex flex-wrap items-center gap-3 rounded-lg bg-error-container px-4 py-3 text-[13px] text-on-error-container">
          {{ error() }}
          <button type="button" (click)="load()" class="rounded-lg bg-transparent px-2 py-1 text-[13px] font-bold underline {{ focus }}">Reintentar</button>
        </p>
      }

      @if (loading()) {
        <div class="space-y-2" role="status" aria-label="Cargando roles">
          @for (n of skeleton; track n) { <div class="h-12 animate-pulse rounded-xl bg-surface-container motion-reduce:animate-none"></div> }
        </div>
      } @else if (roles().length) {
        <ul class="flex flex-wrap gap-x-5 gap-y-1 text-[12px] text-on-surface-variant" aria-label="Cómo leer la matriz">
          <li class="inline-flex items-center gap-1.5"><input type="checkbox" checked disabled class="h-4 w-4 accent-brand-accentDeep" aria-hidden="true" tabindex="-1" /> Lo concede este rol: se puede cambiar</li>
          <li class="inline-flex items-center gap-1.5"><span class="material-symbols-outlined text-[16px]" aria-hidden="true">subdirectory_arrow_right</span> Heredado de otro rol: no se edita aquí</li>
          <li class="inline-flex items-center gap-1.5"><span class="material-symbols-outlined text-[16px]" aria-hidden="true">lock</span> Rol bloqueado: pasa el cursor para ver el motivo</li>
        </ul>

        <section class="glass overflow-x-auto rounded-2xl" aria-label="Matriz de permisos por rol">
          <table class="w-full min-w-[48rem] border-separate border-spacing-0 text-left text-[13px]">
            <caption class="sr-only">Permisos por recurso y acción para cada rol</caption>
            <thead>
              <tr>
                <th scope="col" class="sticky left-0 z-20 min-w-[14rem] border-b border-brand-grey/70 bg-surface-container-lowest px-3 py-2 text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Permiso</th>
                @for (role of roles(); track role.id) {
                  <th scope="col" class="min-w-[9.5rem] border-b border-brand-grey/70 px-2 py-2 align-top" [class.opacity-60]="!role.is_active">
                    <div class="flex flex-col gap-1">
                      <span class="text-[13px] font-bold text-on-surface">{{ role.name }}</span>
                      <span class="flex flex-wrap gap-1">
                        @if (role.is_system) { <span class="rounded-full bg-surface-container px-2 py-0.5 text-[10px] font-bold uppercase text-on-surface-variant">Base</span> }
                        @else { <span class="rounded-full bg-brand-accentLight px-2 py-0.5 text-[10px] font-bold uppercase text-brand-accentDeep">Personalizado</span> }
                        @if (!role.is_active) { <span class="rounded-full bg-error-container px-2 py-0.5 text-[10px] font-bold uppercase text-on-error-container">Inactivo</span> }
                      </span>
                      <span class="text-[11px] font-normal text-on-surface-variant">
                        {{ role.user_count }} {{ role.user_count === 1 ? 'usuario' : 'usuarios' }}@if (role.parent_name) { · hereda de {{ role.parent_name }} }
                      </span>
                      <span class="flex gap-0.5">
                        <button type="button" [class]="iconButton" [attr.aria-label]="'Probar como ' + role.name" title="Probar como este rol" (click)="modal.set({ kind: 'preview', role })">
                          <span class="material-symbols-outlined text-[18px]" aria-hidden="true">visibility</span>
                        </button>
                        <button type="button" [class]="iconButton" [attr.aria-label]="'Editar el rol ' + role.name" title="Editar rol" (click)="modal.set({ kind: 'edit', role })">
                          <span class="material-symbols-outlined text-[18px]" aria-hidden="true">edit</span>
                        </button>
                        <button type="button" [class]="iconButton" [attr.aria-label]="'Eliminar el rol ' + role.name" [title]="deleteBlock(role) || 'Eliminar rol'" [disabled]="!!deleteBlock(role)" (click)="modal.set({ kind: 'delete', role })">
                          <span class="material-symbols-outlined text-[18px]" aria-hidden="true">delete</span>
                        </button>
                      </span>
                    </div>
                  </th>
                }
              </tr>
            </thead>
            @for (group of matrix(); track group.resource) {
              <tbody>
                <tr>
                  <th scope="colgroup" [attr.colspan]="roles().length + 1" class="border-b border-brand-grey/40 bg-surface-container px-3 py-1.5 text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">{{ group.label }}</th>
                </tr>
                @for (row of group.rows; track row.code) {
                  <tr class="hover:bg-surface-container/50">
                    <th scope="row" class="sticky left-0 z-10 border-b border-brand-grey/30 bg-surface-container-lowest px-3 py-1.5 text-[13px] font-semibold text-on-surface" [title]="row.description ?? ''">{{ row.actionLabel }}</th>
                    @for (role of roles(); track role.id) {
                      <td class="border-b border-brand-grey/30 px-2 py-1.5 text-center" [class.bg-brand-accentLight]="isChanged(role, row.code)">
                        @switch (cell(role, row.code).kind) {
                          @case ('inherited') {
                            <span class="inline-flex items-center justify-center gap-1" [title]="'Heredado de ' + from(role, row.code)">
                              <input type="checkbox" checked disabled class="h-4 w-4 accent-brand-accentDeep" [attr.aria-label]="describe(group, row.actionLabel, role) + ': heredado de ' + from(role, row.code)" />
                              <span class="material-symbols-outlined text-[16px] text-on-surface-variant" aria-hidden="true">subdirectory_arrow_right</span>
                            </span>
                          }
                          @default {
                            <span class="inline-flex items-center justify-center gap-1" [title]="locked(role) ?? ''">
                              <input type="checkbox" class="h-4 w-4 accent-brand-accentDeep {{ focus }}" [checked]="cell(role, row.code).kind === 'own'" [disabled]="!!locked(role) || saving()"
                                [attr.aria-label]="describe(group, row.actionLabel, role)" (change)="toggle(role, row.code)" />
                              @if (locked(role)) { <span class="material-symbols-outlined text-[14px] text-on-surface-variant" aria-hidden="true">lock</span> }
                            </span>
                          }
                        }
                      </td>
                    }
                  </tr>
                }
              </tbody>
            }
          </table>
        </section>
      }

      @if (changes().length) {
        <div class="glass sticky bottom-3 z-30 flex flex-wrap items-center justify-between gap-3 rounded-2xl px-5 py-3" role="region" aria-label="Cambios sin guardar">
          <p class="text-[13px] font-semibold text-on-surface" role="status">{{ summary() }}</p>
          <div class="flex gap-2">
            <button type="button" (click)="modal.set({ kind: 'discard' })" [disabled]="saving()" class="rounded-lg bg-transparent px-4 py-2 text-[13px] font-semibold !text-on-surface-variant hover:bg-surface-container disabled:opacity-40 {{ focus }}">Descartar</button>
            <button type="button" (click)="save()" [disabled]="saving()" class="glass-btn rounded-xl px-5 py-2 text-[13px] font-bold transition-colors {{ focus }}">{{ saving() ? 'Guardando…' : 'Guardar cambios' }}</button>
          </div>
        </div>
      }
    </div>

    @switch (modal()?.kind) {
      @case ('create') { <app-role-form-modal [roles]="roles()" [busy]="busy()" [serverError]="formError()" (saved)="create($event)" (closed)="closeModal()" /> }
      @case ('edit') {
        @if (target(); as role) { <app-role-form-modal [role]="role" [roles]="roles()" [busy]="busy()" [serverError]="formError()" (saved)="update(role, $event)" (closed)="closeModal()" /> }
      }
      @case ('preview') {
        @if (target(); as role) { <app-role-preview-modal [role]="role" [preview]="previewOf(role)" [matrix]="matrix()" [unsaved]="changes().length > 0" (closed)="closeModal()" /> }
      }
      @case ('delete') {
        @if (target(); as role) {
          <div class="fixed inset-0 z-[55] flex items-end justify-center p-0 sm:items-center sm:p-4">
            <div class="absolute inset-0 bg-brand-navy/50" (click)="closeModal()" aria-hidden="true"></div>
            <div class="glass relative w-full max-w-md rounded-t-2xl p-5 sm:rounded-2xl" role="alertdialog" aria-modal="true" aria-labelledby="rl-del-title" aria-describedby="rl-del-text">
              <h2 id="rl-del-title" class="text-[16px] font-bold text-on-surface">¿Eliminar el rol «{{ role.name }}»?</h2>
              <p id="rl-del-text" class="mt-2 text-[13px] text-on-surface-variant">Se borra para siempre junto con los permisos que concede. Queda registrado en la auditoría. Si solo quieres que deje de usarse, edítalo y desactívalo.</p>
              @if (formError()) { <p role="alert" class="mt-2 text-[13px] text-error">{{ formError() }}</p> }
              <div class="mt-4 flex justify-end gap-2">
                <button type="button" (click)="closeModal()" class="rounded-lg bg-transparent px-4 py-2 text-[13px] font-semibold !text-on-surface-variant hover:bg-surface-container {{ focus }}">Cancelar</button>
                <button type="button" [disabled]="busy()" (click)="remove(role)" class="rounded-xl bg-[#B91C1C] px-5 py-2 text-[13px] font-bold !text-white hover:bg-[#991B1B] disabled:opacity-50 {{ focus }}">Eliminar</button>
              </div>
            </div>
          </div>
        }
      }
      @case ('discard') {
        <div class="fixed inset-0 z-[55] flex items-end justify-center p-0 sm:items-center sm:p-4">
          <div class="absolute inset-0 bg-brand-navy/50" (click)="closeModal()" aria-hidden="true"></div>
          <div class="glass relative w-full max-w-md rounded-t-2xl p-5 sm:rounded-2xl" role="alertdialog" aria-modal="true" aria-labelledby="rl-dis-title">
            <h2 id="rl-dis-title" class="text-[16px] font-bold text-on-surface">¿Descartar los cambios?</h2>
            <p class="mt-2 text-[13px] text-on-surface-variant">{{ summary() }} Se perderán.</p>
            <div class="mt-4 flex justify-end gap-2">
              <button type="button" (click)="closeModal()" class="rounded-lg bg-transparent px-4 py-2 text-[13px] font-semibold !text-on-surface-variant hover:bg-surface-container {{ focus }}">Seguir editando</button>
              <button type="button" (click)="discard()" class="rounded-xl bg-[#B91C1C] px-5 py-2 text-[13px] font-bold !text-white hover:bg-[#991B1B] {{ focus }}">Descartar</button>
            </div>
          </div>
        </div>
      }
    }
    <app-toast-host />
  `,
})
export class RolesComponent implements OnInit {
  private readonly api = inject(RolesAdminService);
  private readonly toast = inject(ToastService);
  private readonly permissions = inject(PermissionsService);
  private readonly destroyRef = inject(DestroyRef);

  readonly focus = FOCUS;
  readonly iconButton = ICON_BUTTON;
  readonly skeleton = [1, 2, 3, 4, 5];

  readonly roles = signal<RoleAdmin[]>([]);
  readonly catalogue = signal<PermissionInfo[]>([]);
  readonly loading = signal(true);
  readonly error = signal('');
  readonly draft = signal<Draft>(new Map());
  readonly saving = signal(false);
  readonly busy = signal(false);
  readonly formError = signal('');
  readonly modal = signal<Modal>(null);

  readonly matrix = computed<MatrixGroup[]>(() => buildMatrix(this.catalogue()));
  readonly changes = computed(() => draftChanges(this.draft(), this.roles()));
  readonly summary = computed(() => {
    const list = this.changes();
    const grants = list.reduce((sum, change) => sum + change.added.length + change.removed.length, 0);
    return `${grants} ${grants === 1 ? 'cambio' : 'cambios'} sin guardar en ${list.length} ${list.length === 1 ? 'rol' : 'roles'}.`;
  });
  /** El rol sobre el que se abrió el diálogo, siempre con los datos más recientes. */
  readonly target = computed(() => {
    const open = this.modal();
    return open && 'role' in open ? (this.roles().find((role) => role.id === open.role.id) ?? null) : null;
  });
  private readonly cells = computed(() => {
    const map = new Map<string, CellState>();
    const draft = this.draft();
    const roles = this.roles();
    for (const group of this.matrix()) {
      for (const row of group.rows) {
        for (const role of roles) {
          map.set(`${role.id}|${row.code}`, resolveCell(role, row.code, roles, draft));
        }
      }
    }
    return map;
  });

  ngOnInit(): void {
    this.load();
  }

  load(): void {
    this.loading.set(true);
    this.error.set('');
    forkJoin({ roles: this.api.list(), permissions: this.api.permissions() })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: ({ roles, permissions }) => {
          this.roles.set(roles);
          this.catalogue.set(permissions);
          // Los cambios sin guardar de roles que ya no existen se descartan.
          const alive = new Set(roles.map((role) => role.id));
          this.draft.update((draft) => new Map([...draft].filter(([id]) => alive.has(id))));
          this.loading.set(false);
        },
        error: (error) => {
          this.error.set(this.message(error, 'No se pudieron cargar los roles. Inténtalo de nuevo.'));
          this.loading.set(false);
        },
      });
  }

  cell(role: RoleAdmin, code: string): CellState {
    return this.cells().get(`${role.id}|${code}`) ?? { kind: 'none' };
  }

  from(role: RoleAdmin, code: string): string {
    const state = this.cell(role, code);
    return state.kind === 'inherited' ? state.from : '';
  }

  isChanged(role: RoleAdmin, code: string): boolean {
    const wanted = this.draft().get(role.id);
    return !!wanted && wanted.has(code) !== role.own_permissions.includes(code);
  }

  locked(role: RoleAdmin): string | null {
    return lockedReason(role, this.permissions.roles());
  }

  describe(group: MatrixGroup, action: string, role: RoleAdmin): string {
    return `${group.label} · ${action} para ${role.name}`;
  }

  label(code: string): string {
    return permissionLabel(code);
  }

  deleteBlock(role: RoleAdmin): string {
    if (role.is_system) {
      return 'Los roles base no se pueden eliminar.';
    }
    if (role.user_count > 0) {
      return 'Tiene usuarios asignados: reasígnalos primero.';
    }
    if (role.children_count > 0) {
      return 'Otros roles heredan de él: cambia primero su padre.';
    }
    return '';
  }

  previewOf(role: RoleAdmin) {
    return previewRole(role, this.roles(), this.matrix(), this.draft());
  }

  toggle(role: RoleAdmin, code: string): void {
    this.draft.update((draft) => toggleDraft(draft, role, code));
  }

  closeModal(): void {
    this.modal.set(null);
    this.formError.set('');
  }

  discard(): void {
    this.draft.set(new Map());
    this.closeModal();
  }

  async save(): Promise<void> {
    const pending = this.changes();
    if (!pending.length || this.saving()) {
      return;
    }
    this.saving.set(true);
    let done = 0;
    try {
      for (const change of pending) {
        const wanted = [...(this.draft().get(change.role.id) ?? [])];
        const updated = await firstValueFrom(this.api.setPermissions(change.role.id, wanted));
        this.roles.update((list) => list.map((role) => (role.id === updated.id ? updated : role)));
        this.draft.update((draft) => {
          const next = new Map(draft);
          next.delete(change.role.id);
          return next;
        });
        done++;
      }
      // Los permisos heredados de los demás roles cambian con cada guardado: se vuelve a leer todo.
      this.toast.success(done === 1 ? 'Permisos guardados.' : `Permisos guardados en ${done} roles.`);
      this.load();
    } catch (error) {
      this.toast.error(this.message(error, 'No se pudieron guardar los cambios.') + (done ? ` Se guardaron ${done}; el resto sigue pendiente.` : ''));
    } finally {
      this.saving.set(false);
    }
  }

  create(values: RoleFormResult): void {
    this.run(
      this.api.create({ name: values.name, description: values.description || null, parent_role_id: values.parent_role_id, permissions: [] }),
      `Rol «${values.name}» creado. Marca sus permisos en la matriz.`,
      'No se pudo crear el rol.',
    );
  }

  update(role: RoleAdmin, values: RoleFormResult): void {
    const payload: RoleUpdatePayload = {};
    if (values.name !== role.name) payload.name = values.name;
    if ((values.description || null) !== role.description) payload.description = values.description || null;
    if (!role.is_system && values.parent_role_id !== role.parent_role_id) payload.parent_role_id = values.parent_role_id;
    if (!role.is_system && values.is_active !== role.is_active) payload.is_active = values.is_active;
    if (!Object.keys(payload).length) {
      this.closeModal();
      return;
    }
    this.run(this.api.update(role.id, payload), 'Rol actualizado.', 'No se pudo actualizar el rol.');
  }

  remove(role: RoleAdmin): void {
    this.run(this.api.remove(role.id), `Rol «${role.name}» eliminado.`, 'No se pudo eliminar el rol.');
  }

  private run(request: Observable<unknown>, success: string, failure: string): void {
    this.busy.set(true);
    this.formError.set('');
    request.pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
      next: () => {
        this.busy.set(false);
        this.closeModal();
        this.toast.success(success);
        this.load();
      },
      error: (error) => {
        this.busy.set(false);
        this.formError.set(this.message(error, failure));
      },
    });
  }

  private message(error: unknown, fallback: string): string {
    if (error instanceof HttpErrorResponse) {
      const detail = serverRoleMessage((error.error as { detail?: unknown } | null)?.detail);
      if (detail) {
        return detail;
      }
    }
    return apiErrorMessage(error, fallback);
  }
}
