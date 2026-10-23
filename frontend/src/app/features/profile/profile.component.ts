import { AsyncPipe, DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, DestroyRef, OnInit, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';

import { initials } from '../../core/equipment-status';
import { ProfileData } from '../../core/profile.service';
import { ProfileState, ProfileStore } from '../../core/profile.store';
import { ToastHostComponent } from '../../shared/toast-host.component';
import { ProfileHistoryComponent } from './profile-history.component';
import { ProfileSecurityComponent } from './profile-security.component';
import { PROFILE_LIMITS, ProfileFormErrors, avatarFileError, avatarSizeError, imageSize, validateProfile } from './profile-ui';

type Tab = 'datos' | 'seguridad' | 'historial';

const FOCUS = 'focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep';
const FIELD = `mt-1 w-full rounded-lg border border-outline bg-surface-container-lowest px-3 py-2 text-[13px] text-on-surface ${FOCUS} aria-[invalid=true]:border-error disabled:bg-surface-container disabled:text-on-surface-variant`;

/** Mi perfil: datos y foto, seguridad (contraseña y sesiones) e historial propio. */
@Component({
  selector: 'app-profile',
  standalone: true,
  imports: [AsyncPipe, DatePipe, ProfileSecurityComponent, ProfileHistoryComponent, ToastHostComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (vm$ | async; as vm) {
      <div class="space-y-4">
        <header class="glass flex flex-col gap-4 rounded-2xl p-5 sm:flex-row sm:items-center">
          <div class="relative shrink-0">
            @if (vm.avatarUrl) {
              <img [src]="vm.avatarUrl" alt="" width="96" height="96" class="h-24 w-24 rounded-full object-cover shadow" />
            } @else {
              <span class="flex h-24 w-24 items-center justify-center rounded-full bg-[linear-gradient(135deg,#ADD7F6,#A2D2FF)] text-[30px] font-bold text-[#3E5C76]" aria-hidden="true">{{ initialsOf(vm.profile?.full_name ?? '') }}</span>
            }
          </div>
          <div class="min-w-0 flex-1">
            <h1 class="truncate text-[22px] font-extrabold text-on-surface">{{ vm.profile?.full_name }}</h1>
            <p class="truncate text-[13px] text-on-surface-variant">{{ vm.profile?.email }}</p>
            <div class="mt-2 flex flex-wrap gap-2">
              @for (role of vm.profile?.roles ?? []; track role.code) {
                <span class="rounded-full bg-[#DBEAFE] px-2.5 py-0.5 text-[11px] font-bold text-[#1E40AF]">{{ role.name }}</span>
              }
              @if (vm.profile?.employee_code) {
                <span class="rounded-full bg-[#E2E8F0] px-2.5 py-0.5 text-[11px] font-semibold text-[#334155]">Código {{ vm.profile?.employee_code }}</span>
              }
            </div>
            @if (vm.profile?.last_login_at) {
              <p class="mt-2 text-[12px] text-on-surface-variant">Último acceso: {{ vm.profile?.last_login_at | date: "d MMM y, HH:mm" }}</p>
            }
          </div>
          <div class="flex flex-col gap-2 sm:items-end">
            <input #file type="file" class="sr-only" accept="image/png,image/jpeg" aria-label="Elegir foto de perfil" (change)="pickPhoto($event)" />
            <button type="button" (click)="file.click()" [disabled]="vm.busy"
              class="glass-btn flex items-center gap-1.5 rounded-xl px-4 py-2 text-[13px] font-bold transition-colors {{ focus }}">
              <span class="material-symbols-outlined text-[18px]" aria-hidden="true">add_a_photo</span> {{ vm.profile?.has_avatar ? 'Cambiar foto' : 'Subir foto' }}
            </button>
            @if (vm.profile?.has_avatar) {
              <button type="button" (click)="removePhoto()" [disabled]="vm.busy"
                class="rounded-lg bg-transparent px-3 py-1.5 text-[12px] font-semibold !text-[#B91C1C] hover:bg-[#FEF2F2] disabled:opacity-50 {{ focus }}">Quitar foto</button>
            }
            <p class="text-[11px] text-on-surface-variant">PNG o JPG, hasta 2 MB, mínimo 64×64 px.</p>
          </div>
        </header>
        @if (photoError()) {
          <p role="alert" class="rounded-lg bg-error-container px-4 py-3 text-[13px] text-on-error-container">{{ photoError() }}</p>
        }
        @if (vm.error) {
          <p role="alert" class="flex flex-wrap items-center gap-3 rounded-lg bg-error-container px-4 py-3 text-[13px] text-on-error-container">
            {{ vm.error }}
            <button type="button" (click)="store.load()" class="rounded-lg bg-transparent px-2 py-1 text-[13px] font-bold underline {{ focus }}">Reintentar</button>
          </p>
        }

        <div role="tablist" aria-label="Secciones del perfil" class="flex flex-wrap gap-1 border-b border-brand-grey/70">
          @for (t of tabs; track t.id) {
            <button type="button" role="tab" [id]="'tab-' + t.id" [attr.aria-selected]="tab() === t.id" [attr.aria-controls]="'panel-' + t.id"
              [attr.tabindex]="tab() === t.id ? 0 : -1" (click)="tab.set(t.id)" (keydown)="onTabKey($event)"
              class="-mb-px flex items-center gap-1.5 border-b-2 bg-transparent px-4 py-2.5 text-[13px] font-semibold transition-colors {{ focus }}"
              [class]="tab() === t.id ? 'border-brand-accentDeep !text-brand-accentDeep' : 'border-transparent !text-on-surface-variant hover:!text-on-surface'">
              <span class="material-symbols-outlined text-[18px]" aria-hidden="true">{{ t.icon }}</span>{{ t.label }}
            </button>
          }
        </div>

        @switch (tab()) {
          @case ('datos') {
            <section id="panel-datos" role="tabpanel" aria-labelledby="tab-datos">
              @if (vm.profile; as p) {
                <form class="glass grid max-w-3xl grid-cols-1 gap-x-4 gap-y-3 rounded-2xl p-5 sm:grid-cols-2" (submit)="saveData($event, p)" novalidate>
                  <div class="sm:col-span-2">
                    <label for="pf-name" class="text-[12px] font-bold text-on-surface">Nombre completo *</label>
                    <input id="pf-name" type="text" [class]="field" autocomplete="name" [attr.maxlength]="limits.nameMax"
                      [value]="name()" (input)="name.set($any($event.target).value)" [attr.aria-invalid]="!!shown().full_name" aria-describedby="pf-name-err" />
                    <p id="pf-name-err" class="mt-1 min-h-[1rem] text-[12px] text-error" role="alert">{{ shown().full_name }}</p>
                  </div>
                  <div class="sm:col-span-2">
                    <label for="pf-email" class="flex items-center gap-1 text-[12px] font-bold text-on-surface">
                      Correo <span class="material-symbols-outlined text-[14px] text-on-surface-variant" aria-hidden="true">lock</span>
                    </label>
                    <input id="pf-email" type="email" [class]="field" [value]="p.email" disabled readonly aria-describedby="pf-email-hint" />
                    <p id="pf-email-hint" class="mt-1 text-[12px] text-on-surface-variant">Es tu identidad de acceso y no se puede cambiar. Si necesitas otro correo, pídeselo a un administrador.</p>
                  </div>
                  <div>
                    <label for="pf-phone" class="text-[12px] font-bold text-on-surface">Teléfono</label>
                    <input id="pf-phone" type="tel" [class]="field" autocomplete="tel" placeholder="+57 300 123 4567" [attr.maxlength]="limits.phoneMax"
                      [value]="phone()" (input)="phone.set($any($event.target).value)" [attr.aria-invalid]="!!shown().phone" aria-describedby="pf-phone-err" />
                    <p id="pf-phone-err" class="mt-1 min-h-[1rem] text-[12px] text-error" role="alert">{{ shown().phone }}</p>
                  </div>
                  <div>
                    <label for="pf-code" class="flex items-center gap-1 text-[12px] font-bold text-on-surface">
                      Código de empleado <span class="material-symbols-outlined text-[14px] text-on-surface-variant" aria-hidden="true">lock</span>
                    </label>
                    <input id="pf-code" type="text" [class]="field" [value]="p.employee_code ?? 'Sin asignar'" disabled readonly />
                    <p class="mt-1 min-h-[1rem] text-[12px] text-on-surface-variant">Lo asigna un administrador.</p>
                  </div>
                  <div class="flex justify-end gap-2 sm:col-span-2">
                    <button type="button" (click)="resetData(p)" [disabled]="!dirty(p) || vm.busy"
                      class="rounded-lg bg-transparent px-4 py-2 text-[13px] font-semibold !text-on-surface-variant hover:bg-surface-container disabled:opacity-40 {{ focus }}">Descartar</button>
                    <button type="submit" [disabled]="!dirty(p) || vm.busy"
                      class="glass-btn rounded-xl px-5 py-2 text-[13px] font-bold transition-colors {{ focus }}">{{ vm.busy ? 'Guardando…' : 'Guardar cambios' }}</button>
                  </div>
                </form>
              }
            </section>
          }
          @case ('seguridad') {
            <section id="panel-seguridad" role="tabpanel" aria-labelledby="tab-seguridad"><app-profile-security /></section>
          }
          @case ('historial') {
            <section id="panel-historial" role="tabpanel" aria-labelledby="tab-historial"><app-profile-history /></section>
          }
        }
      </div>
      <app-toast-host />
    }
  `,
})
export class ProfileComponent implements OnInit {
  readonly store = inject(ProfileStore);
  private readonly destroyRef = inject(DestroyRef);

  readonly vm$ = this.store.state$;
  readonly focus = FOCUS;
  readonly field = FIELD;
  readonly limits = PROFILE_LIMITS;
  readonly initialsOf = initials;
  readonly tabs: { id: Tab; label: string; icon: string }[] = [
    { id: 'datos', label: 'Mis datos', icon: 'person' },
    { id: 'seguridad', label: 'Seguridad', icon: 'shield_lock' },
    { id: 'historial', label: 'Historial', icon: 'history' },
  ];

  readonly tab = signal<Tab>('datos');
  readonly name = signal('');
  readonly phone = signal('');
  readonly submitted = signal(false);
  readonly photoError = signal('');
  private loaded: ProfileData | null = null;

  ngOnInit(): void {
    this.store.load();
    this.store.state$.pipe(takeUntilDestroyed(this.destroyRef)).subscribe((state) => this.syncForm(state));
  }

  /** Rellena el formulario cuando llega el perfil (o cambia desde fuera), sin pisar lo que se escribe. */
  private syncForm(state: ProfileState): void {
    const profile = state.profile;
    if (profile && profile !== this.loaded) {
      this.loaded = profile;
      this.name.set(profile.full_name);
      this.phone.set(profile.phone ?? '');
      this.submitted.set(false);
    }
  }

  private errors(): ProfileFormErrors {
    return validateProfile({ full_name: this.name(), phone: this.phone() });
  }

  shown(): ProfileFormErrors {
    return this.submitted() ? this.errors() : {};
  }

  dirty(profile: ProfileData): boolean {
    return this.name().trim().replace(/\s+/g, ' ') !== profile.full_name || this.phone().trim().replace(/\s+/g, ' ') !== (profile.phone ?? '');
  }

  resetData(profile: ProfileData): void {
    this.name.set(profile.full_name);
    this.phone.set(profile.phone ?? '');
    this.submitted.set(false);
  }

  saveData(event: Event, profile: ProfileData): void {
    event.preventDefault();
    this.submitted.set(true);
    const errors = this.errors();
    if (errors.full_name || errors.phone || !this.dirty(profile)) {
      return;
    }
    this.store
      .update({ full_name: this.name().trim().replace(/\s+/g, ' '), phone: this.phone().trim().replace(/\s+/g, ' ') || null })
      .subscribe();
  }

  async pickPhoto(event: Event): Promise<void> {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    input.value = ''; // permite elegir de nuevo el mismo archivo
    this.photoError.set('');
    if (!file) {
      return;
    }
    const problem = avatarFileError(file);
    if (problem) {
      this.photoError.set(problem);
      return;
    }
    try {
      const { width, height } = await imageSize(file);
      const small = avatarSizeError(width, height);
      if (small) {
        this.photoError.set(small);
        return;
      }
    } catch {
      this.photoError.set('El archivo no es una imagen válida. Sube un PNG o JPG.');
      return;
    }
    this.store.uploadAvatar(file).subscribe();
  }

  removePhoto(): void {
    this.photoError.set('');
    this.store.removeAvatar().subscribe();
  }

  /** Flechas izquierda/derecha entre pestañas, como en un tablist estándar. */
  onTabKey(event: KeyboardEvent): void {
    const step = event.key === 'ArrowRight' ? 1 : event.key === 'ArrowLeft' ? -1 : 0;
    if (!step) {
      return;
    }
    event.preventDefault();
    const index = this.tabs.findIndex((t) => t.id === this.tab());
    const next = this.tabs[(index + step + this.tabs.length) % this.tabs.length];
    this.tab.set(next.id);
    queueMicrotask(() => document.getElementById('tab-' + next.id)?.focus());
  }

}
